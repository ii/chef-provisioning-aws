require 'chef/provisioning/aws_driver/aws_resource'
require 'chef/resource/aws_route53_record_set'
require 'securerandom'

# the AWS API doesn't have these objects linked, so give it some help.
class Aws::Route53::Types::HostedZone
  attr_accessor :resource_record_sets
end

class Aws::Route53::Types::ResourceRecordSet
  def aws_key
    "#{name.sub(/\.$/, '')}, #{type}"
  end

  # the API doesn't seem to provide any facility to convert these types into the data structures used by the
  # API; see http://redirx.me/?t3za for the RecordSet type specifically.
  def to_change_struct
    {
      name: name,
      type: type,
      ttl: ttl,
      resource_records: resource_records.map {|r| {:value => r.value}},
    }
  end
end

class Chef::Resource::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSResourceWithEntry

  aws_sdk_type ::Aws::Route53::Types::HostedZone, load_provider: false

  resource_name :aws_route53_hosted_zone

  # name of the domain. AWS will tack on a trailing dot, so we're going to prohibit it here for consistency:
  # the name is our data bag key, and if a user has "foo.com" in one resource and "foo.com." in another, Route
  # 53 will happily accept two different domains it calls "foo.com.".
  attribute :name, kind_of: String, callbacks: { "domain name cannot end with a dot" => lambda { |n| n !~ /\.$/ } }

  # The comment included in the CreateHostedZoneRequest element. String <= 256 characters.
  attribute :comment, kind_of: String

  attribute :aws_route53_zone_id, kind_of: String, aws_id_attribute: true

  def record_sets(&block)
    if block_given?
      @record_sets_block = block
    else
      @record_sets_block
    end
  end

  def aws_object
    driver, id = get_driver_and_id
    result = driver.route53_client.get_hosted_zone(id: id).hosted_zone if id rescue nil
    if result
      result.resource_record_sets = get_record_sets_from_aws(result.id).resource_record_sets
      result
    else
      nil
    end
  end

  # since this is used exactly once, it could plausibly be inlined in #aws_object.
  def get_record_sets_from_aws(hosted_zone_id, opts={})
    params = { hosted_zone_id: hosted_zone_id }.merge(opts)
    driver.route53_client.list_resource_record_sets(params)
  end
end

class Chef::Provider::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSProvider

  provides :aws_route53_hosted_zone
  use_inline_resources

  CREATE = "CREATE"
  UPDATE = "UPSERT"
  DELETE = "DELETE"
  RRS_COMMENT = "Managed by chef-provisioning-aws"

  attr_accessor :record_set_list

  def make_hosted_zone_config(new_resource)
    config = {}
    # add :private_zone here once VPC validation is enabled.
    [:comment].each do |attr|
      value = new_resource.send(attr)
      if value
        config[attr] = value
      end
    end
    config
  end

  def create_aws_object

    converge_by "create new Route 53 zone #{new_resource}" do

      # AWS stores some attributes off to the side here.
      hosted_zone_config = make_hosted_zone_config(new_resource)

      values = {
        name: new_resource.name,
        hosted_zone_config: hosted_zone_config,
        caller_reference: "chef-provisioning-aws-#{SecureRandom.uuid.upcase}",  # required, unique each call
      }

      zone = new_resource.driver.route53_client.create_hosted_zone(values).hosted_zone
      new_resource.aws_route53_zone_id(zone.id)

        begin
          record_set_resources = get_record_sets_from_resource(new_resource)

          if record_set_resources

            change_list = record_set_resources.map { |rs| rs.to_aws_change_struct(CREATE) }

            new_resource.driver.route53_client.change_resource_record_sets(hosted_zone_id: new_resource.aws_route53_zone_id,
                                                                           change_batch: {
                                                                             comment: RRS_COMMENT,
                                                                             changes: change_list,
                                                                             })
          end
        rescue => ex
          # the change call is transactional, so we just need to clean up the zone we created.
          new_resource.driver.route53_client.delete_hosted_zone(id: zone.id)
          raise
        end
      zone
    end
  end

  def update_aws_object(hosted_zone)

    new_resource.aws_route53_zone_id(hosted_zone.id)

    converge_by "update Route 53 zone #{new_resource}" do

      if new_resource.comment != hosted_zone.config.comment
        new_resource.driver.route53_client.update_hosted_zone_comment(id: hosted_zone.id, comment: new_resource.comment)
      end

      begin
        record_set_resources = get_record_sets_from_resource(new_resource)
        if record_set_resources
          aws_record_sets = hosted_zone.resource_record_sets

          change_list = []

          # we already checked for duplicate Chef RR resources in #get_record_sets_from_resource.
          keyed_chef_resources = record_set_resources.reduce({}) { |coll, rs| coll[rs.aws_key] = rs; coll }
          keyed_aws_objects    = aws_record_sets.reduce({})      { |coll, rs| coll[rs.aws_key] = rs; coll }

          # TODO: implement :destroy for RRs.
          keyed_chef_resources.each do |key, chef_resource|
            if keyed_aws_objects.has_key?(key) &&
              chef_resource.to_aws_struct != keyed_aws_objects[key].to_change_struct
              action = chef_resource.action.first == :destroy ? DELETE : UPDATE
              change_list << chef_resource.to_aws_change_struct(action)
            end
          end


          if change_list.size > 0
            new_resource.driver.route53_client.change_resource_record_sets(hosted_zone_id: new_resource.aws_route53_zone_id,
                                                                           change_batch: {
                                                                             comment: RRS_COMMENT,
                                                                             changes: change_list,
                                                                             })
          else
            Chef::Log.info("All aws_route53_record_set resources up to date (nothing to do).")
          end
        end
      rescue => ex
        # the RecordSet change is transactional, but we must revert the comment manually.
        if new_resource.comment != hosted_zone.config.comment
          new_resource.driver.route53_client.update_hosted_zone_comment(id: hosted_zone.id, comment: hosted_zone.config.comment)
        end
        raise
      end
    end
  end

  def destroy_aws_object(hosted_zone)
    converge_by "delete Route53 zone #{new_resource}" do
      Chef::Log.info("Deleting all non-SOA/NS records for #{hosted_zone.name}")

      rr_changes = hosted_zone.resource_record_sets.reject { |aws_rr|
        %w{SOA NS}.include?(aws_rr.type)
        }.map { |aws_rr|
          {
            action: DELETE,
            resource_record_set: aws_rr.to_change_struct,
          }
        }

      if rr_changes.size > 0
        aws_struct = {
          hosted_zone_id: hosted_zone.id,
          change_batch: {
            comment: "Purging RRs prior to deleting resource",
            changes: rr_changes,
          }
        }

        new_resource.driver.route53_client.change_resource_record_sets(aws_struct)
      end

      result = new_resource.driver.route53_client.delete_hosted_zone(id: hosted_zone.id)
    end
  end

  # `record_sets` is defined on the `aws_route53_hosted_zone` resource as a block attribute, so compile that,
  # validate it, and return a list of AWSRoute53RecordSet resource objects.
  def get_record_sets_from_resource(new_resource)

    return nil unless new_resource.record_sets
    instance_eval(&new_resource.record_sets)

    # because we're in the provider, the RecordSet resource happen in their own mini Chef run, and they're the
    # only things in the resource_collection.
    record_set_resources = run_context.resource_collection.to_a
    return nil unless record_set_resources

    record_set_resources.each do |rs|
      rs.aws_route53_zone_id(new_resource.aws_route53_zone_id)
      rs.validate!
    end

    Chef::Resource::AwsRoute53RecordSet.verify_unique!(record_set_resources)
    record_set_resources
  end
end

require 'chef/provisioning/aws_driver/aws_resource'
require 'chef/resource/aws_route53_record_set'
require 'securerandom'

# the AWS API doesn't have these objects linked, so give it some help.
class Aws::Route53::Types::HostedZone
  attr_accessor :resource_record_sets
end

# the API doesn't seem to provide any facility to convert these types into the data structures used by the
# API; see http://redirx.me/?t3za for the RecordSet type specifically.
class Aws::Route53::Types::RecordSet
  def to_change_struct
    {
      name: name,
      type: type,
      ttl: ttl,
      resource_records: [resource_records.map {|r| [:value, r.value]}.to_h],
    }
  end
end

class Chef::Resource::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSResourceWithEntry

  aws_sdk_type ::Aws::Route53::Types::HostedZone, load_provider: false

  resource_name :aws_route53_hosted_zone

  # name of the domain. unlike an RR name, this can (must?) have a trailing dot.
  attribute :name, kind_of: String, name_attribute: true

  # The comment included in the CreateHostedZoneRequest element. String <= 256 characters.
  attribute :comment, kind_of: String

  attribute :aws_route53_zone_id, kind_of: String, aws_id_attribute: true

  def record_sets(&block)
    if block_given?
      node.default[:aws_route53_recordsets] = []
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

  def get_record_sets_from_aws(hosted_zone_id, opts={})
    params = { hosted_zone_id: hosted_zone_id }.merge(opts)
    driver.route53_client.list_resource_record_sets(params)
  end
end

class Chef::Provider::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSProvider

  provides :aws_route53_hosted_zone
  use_inline_resources

  attr_accessor :record_set_list

  def make_hosted_zone_config(new_resource)
    config = {}
    # add :private_zone here once validation is enabled.
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

      # a "private" zone must have a VPC associated, *and* from the UI it looks like the VPC must have
      # 'enableDnsHostnames' and 'enableDnsSupport' both set to true. see docs: http://redirx.me/?t3zr

      zone = new_resource.driver.route53_client.create_hosted_zone(values).hosted_zone
      new_resource.aws_route53_zone_id(zone.id)

      record_set_list = get_record_sets_from_resource(new_resource, zone)
      if record_set_list
        change_record_sets(new_resource, record_set_list)
      end

      zone
    end
  end

  def update_aws_object(hosted_zone)
    # record_set_list = get_record_sets_from_resource(new_resource, hosted_zone)

    if new_resource.comment != hosted_zone.config.comment
      converge_by "update Route 53 zone #{new_resource}" do
        new_resource.driver.route53_client.update_hosted_zone_comment(id: hosted_zone.id, comment: new_resource.comment)
      end
    end
  end

  def destroy_aws_object(hosted_zone)

    if purging
      Chef::Log.info("Deleting all non-SOA/NS records for #{hosted_zone.name}")
      rr_changes = hosted_zone.resource_record_sets.reject { |aws_rr|
        %w{SOA NS}.include?(aws_rr.type)
        }.map { |aws_rr|
          {
            action: "DELETE",
            resource_record_set: {
              name: aws_rr.name,
              type: aws_rr.type,
              ttl: aws_rr.ttl,
              resource_records: [aws_rr.resource_records.map {|r| [:value, r.value]}.to_h],
            }
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
    end

    converge_by "delete Route53 zone #{new_resource}" do
      result = new_resource.driver.route53_client.delete_hosted_zone(id: hosted_zone.id)
    end
  end

  def get_record_sets_from_resource(new_resource, hosted_zone)

    return nil unless new_resource.record_sets
    instance_eval(&new_resource.record_sets)

    # pretty fuzzy on whether this is right or why it seems to work.
    record_sets = run_context.resource_collection.to_a
    return nil unless record_sets

    record_sets.each do |rs|
      rs.validate!
    end

    Chef::Resource::AwsRoute53RecordSet.verify_unique!(record_sets)
    record_sets
  end

  def change_record_sets(new_resource, record_set_list)
    return
    Chef::Log.warn "attempting to submit RR: #{new_resource.record_set_list}"
    aws_struct = record_set_list.map { |rs| rs.to_aws_struct("UPSERT") }
    puts "\n#{aws_struct}"

    begin
      result = new_resource.driver.route53_client.change_resource_record_sets(hosted_zone_id: new_resource.aws_route53_zone_id,
                                                                              change_batch: {
                                                                               comment: "Managed by Chef",
                                                                               changes: aws_struct,
                                                                               })
    rescue StandardError => ex
        # puts "\n"
        # Chef::Log.warn "#{ex.class}: #{ex.message}"
      raise
    end
  end

end

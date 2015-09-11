require 'chef/provisioning/aws_driver/aws_resource'
require 'chef/resource/aws_route53_record_set'
require 'securerandom'

class Chef::Resource::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSResourceWithEntry

  aws_sdk_type ::Aws::Route53::Types::HostedZone, load_provider: false

  resource_name :aws_route53_hosted_zone

  # name of the domain. unlike the RR name, this can (must?) have a trailing dot.
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
    result || nil
  end
end

class Chef::Provider::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSProvider

  provides :aws_route53_hosted_zone
  use_inline_resources

  attr :record_set_list

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

      process_record_sets(run_context.resource_collection, new_resource, zone)

      zone
    end
  end

  def process_record_sets(record_sets, new_resource, hosted_zone)
    return unless record_sets

    record_sets.each do |rs|
      rs.validate!
    end
    record_set_list = record_sets.to_a
  end

  def update_aws_object(hosted_zone)
    instance_eval(&new_resource.record_sets)

    process_record_sets(run_context.resource_collection, new_resource, hosted_zone)

    if new_resource.comment != hosted_zone.config.comment
      converge_by "update Route 53 zone #{new_resource}" do
        new_resource.driver.route53_client.update_hosted_zone_comment(id: hosted_zone.id, comment: new_resource.comment)
      end
    end
  end

  def change_record_sets(new_resource, zone)
    if new_resource.record_sets
      # rs_param = RecordSet.get_recordsets(new_resource.record_sets).map { |rs| rs.to_hash }
      Chef::Log.warn "attempting to submit RR: #{new_resource.record_sets}"
      begin
        result = new_resource.driver.route53_client.change_resource_record_sets(hosted_zone_id: zone.id,
                                                                       change_batch: {
                                                                        comment: "Change the RRs",
                                                                        changes: new_resource.record_sets,
                                                                        })
      rescue StandardError => ex
        # puts "\n"
        # Chef::Log.warn "#{ex.class}: #{ex.message}"
        raise
      end
    end
  end

  def destroy_aws_object(hosted_zone)
    converge_by "delete Route53 zone #{new_resource}" do
      result = new_resource.driver.route53_client.delete_hosted_zone(id: hosted_zone.id)
    end
  end
end

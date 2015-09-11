require 'chef/provisioning/aws_driver/aws_resource'
require 'record_set'
require 'securerandom'

class Chef::Resource::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSResourceWithEntry

  aws_sdk_type ::Aws::Route53::Types::HostedZone, load_provider: false

  resource_name :aws_route53_hosted_zone

  # name of the domain. unlike the RR name, this can (must?) have a trailing dot.
  attribute :name, kind_of: String, name_attribute: true

  # The comment included in the CreateHostedZoneRequest element. String <= 256 characters.
  attribute :comment, kind_of: String

  attribute :aws_route53_zone_id, kind_of: String, aws_id_attribute: true

  attribute :record_sets, kind_of: Array #, callbacks: lambda { |p| RecordSet.get_recordsets(p) }

  # private_zone can only be set if a VPC is attached.
  # attribute :private_zone, kind_of: [TrueClass, FalseClass]
  # attribute :vpcs

  def aws_object
    driver, id = get_driver_and_id
    result = driver.route53_client.get_hosted_zone(id: id).hosted_zone if id rescue nil
    result || nil
  end
end

class Chef::Resource::RecordSet < Chef::Resource::LWRPBase
  attribute :aws_hosted_zone_id, kind_of: String, required: true

  # if you add the trailing dot yourself, you get "FATAL problem: DomainLabelEmpty encountered"
  attribute :rr_name, required: true, callbacks: { "cannot end with a dot" => lambda { |n| n !~ /\.$/ }}
  attribute :value, required: true   # may not be required.
  attribute :type, equal_to: %w(SOA A TXT NS CNAME MX PTR SRV SPF AAAA), required: true
  attribute :ttl, kind_of: Fixnum, required: true
end

class Chef::Provider::AwsRoute53HostedZone < Chef::Provisioning::AWSDriver::AWSProvider

  provides :aws_route53_hosted_zone
  use_inline_resources

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
      change_record_sets(new_resource, zone)

      zone
    end
  end

  def update_aws_object(hosted_zone)
    if new_resource.comment != hosted_zone.config.comment
      converge_by "update Route 53 zone #{new_resource}" do
        new_resource.driver.route53_client.update_hosted_zone_comment(id: hosted_zone.id, comment: new_resource.comment)
      end
    end

    new_resource.record_sets.map { |r| r[:resource_record_set] }.each do |raw_rs|
      rs = Chef::Resource::RecordSet.new("#{raw_rs[:name]} #{raw_rs[:type]}").tap do |resource|
        resource.rr_name(raw_rs[:name])
        resource.value(raw_rs[:resource_records][0][:value])
        resource.type(raw_rs[:type])
        # resource.ttl(raw_rs[:ttl])
      end
      require 'pry'; binding.pry
    end
    # change_record_sets(new_resource, hosted_zone)
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
        require 'pry'; binding.pry
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

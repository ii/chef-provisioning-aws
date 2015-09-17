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

class Chef::Resource::AwsRoute53RecordSet < Chef::Resource::LWRPBase

  actions :create, :destroy
  default_action :create

  resource_name :aws_route53_record_set
  attribute :aws_route53_zone_id, kind_of: String, required: true

  # if you add the trailing dot yourself, you get "FATAL problem: DomainLabelEmpty encountered"
  attribute :rr_name, required: true, callbacks: { "cannot end with a dot" => lambda { |n| n !~ /\.$/ }}
  attribute :value   # may not be required for some types.
  attribute :type, equal_to: %w(SOA A TXT NS CNAME MX PTR SRV SPF AAAA), required: true
  attribute :ttl, kind_of: Fixnum, required: true
  attribute :resource_records, kind_of: Array, required: true


  def validate!
    [:rr_name, :type, :ttl, :value].each { |f| self.send(f) }
  end

  def aws_key
    "#{rr_name}, #{type}"
  end

  def to_aws_struct
    {
      name: rr_name,
      type: type,
      ttl: ttl,
      resource_records: resource_records,
    }
  end

  def to_aws_change_struct(aws_action)
    # there are more elements which are optional, notably 'weight' and 'region': see the API doc at
    # http://redirx.me/?t3zo
    {
      action: aws_action,
      resource_record_set: self.to_aws_struct
    }
  end

  def self.verify_unique!(record_sets)
    seen = {}

    record_sets.each do |rs|
      key = "#{rs.rr_name}, #{rs.type}"
      if seen.has_key?(key)
        raise Chef::Exceptions::ValidationFailed.new("Duplicate RecordSet found in resource: [#{key}]")
      else
        seen[key] = 1
      end
    end

    # TODO: be helpful and print out all duplicates, not just the first.

    true
  end
end

class Chef::Provider::AwsRoute53RecordSet < Chef::Provider::LWRPBase
  provides :aws_route53_record_set

  # to make RR changes in transactional batches, it has to be done in the parent resource.
  action :create do
  end

  action :destroy do
  end
end


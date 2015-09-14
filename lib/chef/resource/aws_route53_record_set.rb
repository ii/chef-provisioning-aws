class Chef::Resource::AwsRoute53RecordSet < Chef::Resource::LWRPBase

  actions :nothing, :validate, :create, :delete
  default_action :nothing

  resource_name :aws_route53_record_set
  attribute :aws_hosted_zone_id, kind_of: String, required: true

  # if you add the trailing dot yourself, you get "FATAL problem: DomainLabelEmpty encountered"
  attribute :rr_name, required: true, callbacks: { "cannot end with a dot" => lambda { |n| n !~ /\.$/ }}
  attribute :value   # may not be required for some types.
  attribute :type, equal_to: %w(SOA A TXT NS CNAME MX PTR SRV SPF AAAA), required: true
  attribute :ttl, kind_of: Fixnum, required: true
  attribute :resource_records, kind_of: Array, required: true
  attribute :hosted_zone_name, kind_of: String


  def validate!
    [:rr_name, :type, :ttl, :value].each { |f| self.send(f) }
  end

  def to_aws_struct(new_action=nil)
    # there are more elements which are optional, notably 'weight' and 'region': see the API doc at
    # http://redirx.me/?t3zo
    aws_action = new_action || if action.first == :create
      "UPSERT"
    else
      "DELETE"
    end

    Chef::Log.info("Action '#{aws_action}' for RR [#{rr_name}, #{type}]")

    {
      action: aws_action,
      resource_record_set: {
        name: rr_name,
        type: type,
        ttl: ttl,
        resource_records: resource_records,
      }
    }
  end

  def self.verify_unique!(record_sets)
    seen = {}

    record_sets.each do |rs|
      key = "#{rs.rr_name}, #{rs.type}"
      if seen.has_key?(key)
        raise Exceptions::ValidationFailed("Duplicate RecordSet found in resource: [#{key}]")
      else
        seen[key] = 1
      end
    end

    true
  end
end

class Chef::Provider::AwsRoute53RecordSet < Chef::Provider::LWRPBase
  provides :aws_route53_recordset

  # action :validate do
  #   new_resource.validate!
  # end

  # action :create do
  # end

  # action :delete do
  # end
end

  # 'changes' points to an array of these:
  # {
  #   action: "UPSERT", # required, accepts CREATE, DELETE, UPSERT
  #   resource_record_set: { # required
  #     name: "some-api-host.#{zone_name}", # required
  #     type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
  #     ttl: 3600,
  #     resource_records: [
  #       {
  #         value: "some-other-host.example.com.", # required
  #       },
  #     ],
  #   },
  # },


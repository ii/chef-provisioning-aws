class Chef::Resource::AwsRoute53RecordSet < Chef::Resource::LWRPBase

  actions :nothing
  default_action :nothing

  resource_name :aws_route53_record_set
  attribute :aws_hosted_zone_id, kind_of: String, required: true

  # if you add the trailing dot yourself, you get "FATAL problem: DomainLabelEmpty encountered"
  attribute :rr_name, required: true, callbacks: { "cannot end with a dot" => lambda { |n| n !~ /\.$/ }}
  attribute :value   # may not be required for some types.
  attribute :type, equal_to: %w(SOA A TXT NS CNAME MX PTR SRV SPF AAAA), required: true
  attribute :ttl, kind_of: Fixnum, required: true
  attribute :resource_records, kind_of: Array
  attribute :hosted_zone_name, kind_of: String

  def validate!
    [:rr_name, :type, :ttl].each { |f| self.send(f) }
  end
end

# class Chef::Provider::AwsRoute53RecordSet < Chef::Provider::LWRPBase
#   provides :aws_route53_recordset
# end

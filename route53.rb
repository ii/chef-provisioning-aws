#!/usr/bin/env chef-client -z

require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

zone_name = "cdoherty-aws-development-delete-me.com"

# aws_route53_hosted_zone zone_name do
#   action :destroy
# end

require 'securerandom'

rs = [ # required
    {
      action: "UPSERT", # required, accepts CREATE, DELETE, UPSERT
      resource_record_set: { # required
        name: "some-api-host.#{zone_name}", # required
        type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
        ttl: 3600,
        resource_records: [
          {
            value: "some-other-host.example.com.", # required
          },
        ],
      },
    },
  ]

# if aws_route53_recordset only supports :nothing, and in_aws_route53_hosted_zone runs at
# compile-time, I think the latter can stick the RecordSets in a data structure that 
# aws_route53_hosted_zone can access at converge time?

aws_route53_hosted_zone "home.example.com" do
  action :nothing
  comment "The zone stands alone."
end

in_aws_route53_hosted_zone "home.example.com" do |zone_name|
  aws_route53_recordset "something.#{zone_name} CNAME" do
    rr_name "some-api-host.example.com"
    type "CNAME"
    ttl 3600
    resource_records [{ value: "some-other-host.example.com."}]
    hosted_zone_name zone_name
  end

  aws_route53_recordset "something.#{zone_name} A" do
    rr_name "some-api-host.example.com"
    type "A"
    ttl 3600
    resource_records [
      { value: "141.222.2.2",   weight: 10 },
      { value: "192.168.10.89", weight: 20 },
    ]
    hosted_zone_name zone_name
  end
end

  # comment "Contact Chris Doherty <cdoherty@chef.io> with questions about this. "

# aws_route53_hosted_zone zone_name do
#   action :create
#   comment "This is an updated comment."
# end

# aws_route53_recordset "test-host" do
#   aws_hosted_zone_id "/hostedzone/Z28HIS3EPSQP2R"
#   # action :update
# end

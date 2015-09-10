#!/usr/bin/env chef-client -z

require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

zone_name = "cdoherty-aws-development-delete-me.com."

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
        ttl: 1,
        resource_records: [
          {
            value: "some-other-host.example.com.", # required
          },
        ],
      },
    },
  ]

aws_route53_hosted_zone zone_name do
  action :create
  comment "Contact Chris Doherty <cdoherty@chef.io> with questions about this. "
  record_sets rs
end

# aws_route53_hosted_zone zone_name do
#   action :create
#   comment "This is an updated comment."
# end

# aws_route53_recordset "test-host" do
#   aws_hosted_zone_id "/hostedzone/Z28HIS3EPSQP2R"
#   # action :update
# end

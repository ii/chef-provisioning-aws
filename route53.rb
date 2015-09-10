#!/usr/bin/env chef-client -z

require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

zone_name = "cdoherty-aws-development-delete-me.com."

aws_route53_hosted_zone zone_name do
  action :destroy
end

rs = [ # required
    {
      action: "UPSERT", # required, accepts CREATE, DELETE, UPSERT
      resource_record_set: { # required
        name: "target.example.com.", # required
        type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
        set_identifier: "ResourceRecordSetIdentifier",
        weight: 1,
        region: "us-east-1", # accepts us-east-1, us-west-1, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, sa-east-1, cn-north-1
        geo_location: {
          continent_code: "GeoLocationContinentCode",
          country_code: "GeoLocationCountryCode",
          subdivision_code: "GeoLocationSubdivisionCode",
        },
        failover: "PRIMARY", # accepts PRIMARY, SECONDARY
        ttl: 1,
        resource_records: [
          {
            value: "RData", # required
          },
        ],
        alias_target: {
          hosted_zone_id: "ResourceId", # required
          dns_name: "DNSName", # required
          evaluate_target_health: true, # required
        },
        health_check_id: "HealthCheckId",
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

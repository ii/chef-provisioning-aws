#!/usr/bin/env chef-client -z

require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

zone_name = "cdoherty-aws-development-delete-me.com"

aws_route53_hosted_zone zone_name do
  action :purge
end

# if aws_route53_recordset only supports :nothing, and in_aws_route53_hosted_zone runs at
# compile-time, I think the latter can stick the RecordSets in a data structure that 
# aws_route53_hosted_zone can access at converge time?

# log "first log resource" do
#   action :nothing
# end

aws_route53_hosted_zone zone_name do
  action :create
  comment "The zone stands alone."
  record_sets {
    aws_route53_record_set "some-hostname CNAME" do
      rr_name "some-api-host.example.com"
      type "CNAME"
      ttl 3600
      resource_records [{ value: "some-other-host.example.com."}]
    end

    aws_route53_record_set "something A" do
      rr_name "some-api-host.#{zone_name}"
      type "A"
      ttl 3600
      resource_records [
        { value: "141.222.2.2"   },
        { value: "192.168.10.89" },
      ]
      hosted_zone_name zone_name
    end
  }
end

# aws_route53_hosted_zone zone_name do
#   action :purge
# end


# log "second log resource"

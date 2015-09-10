#!/usr/bin/env chef-client -z

require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

zone_name = "cdoherty-aws-development-delete-me.com."
# zone_name = "aws-development-delete-me-#{Time.now.to_i % 1000}.com."

aws_route53_hosted_zone zone_name do
  action :nothing
  comment "Contact Chris Doherty <cdoherty@chef.io> with questions about this. "
end

# aws_route53_hosted_zone zone_name do
#   action :create
#   comment "This is an updated comment."
# end

# aws_route53_recordset "test-host" do
#   aws_hosted_zone_id "/hostedzone/Z28HIS3EPSQP2R"
#   # action :update
# end

# aws_route53_hosted_zone zone_name do
#   action :destroy
# end

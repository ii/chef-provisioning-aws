require 'chef/provisioning/aws_driver'

with_driver 'aws::us-east-1'

# this will fail. we use the domain name as a data bag key, but Route 53 will add a trailing dot, and
# furthermore Route 53 is content to have two HostedZones named "feegle.com.". in order to prevent unexpected
# results, we prevent domain names from ending with a dot.
aws_route53_hosted_zone "feegle.com."

# create a Route 53 Hosted Zone (which AWS will normalize to "feegle.com.").
aws_route53_hosted_zone "feegle.com"

# create a Route 53 Hosted Zone with a CNAME record.
aws_route53_hosted_zone "feegle.com" do
  record_sets {
    aws_route53_record_set "some-hostname CNAME" do
      rr_name "some-api-host.feegle.com"
      type "CNAME"
      ttl 3600
      resource_records [{ value: "some-other-host"}]
    end
  }
end

# Route 53 ResourceRecordSets are mostly analogous to DNS resource records (RRs). in the AWS Console they look
# like first-class objects, but they don't have an AWS ID: only the RR name.

# TODO(9/17/15): the 'rr_name' attribute separate from 'name' appears to not actually be needed--mistake on
# cdoherty's part. it should be an optional override of 'name', like we find in many Chef resources
# ('execute', 'file', etc.).

# aws_route53_record_sets in the same aws_route53_hosted_zone resource are run as a transaction by AWS. you
# cannot currently (9/17/15) define an aws_route53_record_set elsewhere and refer to it here, and in fact I'm
# not sure if that's possible. you could probably define the record_sets block elsewhere and pass it to the
# resource, though.
aws_route53_hosted_zone "feegle.com" do
  record_sets {
    aws_route53_record_set "a-CNAME-host" do
      rr_name "a-CNAME-host.feegle.com"
      type "CNAME"
      ttl 1800
      resource_records [{ value: "a-different-host"}]
    end

    aws_route53_record_set "an-A-host" do
      rr_name "an-A-host.feegle.com"
      type "A"
      ttl 3600
      resource_records [
        { value: "141.222.2.2"   },
        { value: "192.168.10.89" },
      ]
    end
  }
end

# delete an individual RecordSet. the values must be the same as those currently in Route 53, or else an AWS
# error will bubble up.
aws_route53_hosted_zone "feegle.com" do
  record_sets {
    aws_route53_record_set "some-hostname CNAME" do
      action :destroy
      rr_name "some-api-host.feegle.com"
      type "CNAME"
      ttl 1800
      resource_records [{ value: "a-different-host"}]
    end
  }
end

# calling :destroy on a zone will unconditionally wipe all of its RecordSets.
aws_route53_hosted_zone "feegle.com" do
  action :destroy
end

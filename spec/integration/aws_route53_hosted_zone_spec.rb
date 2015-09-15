require 'spec_helper'

describe Chef::Resource::AwsRoute53HostedZone do
  extend AWSSupport

  when_the_chef_12_server "exists", organization: 'foo', server_scope: :context do
    with_aws "when connected to AWS" do

      let(:zone_name) { "aws-spec-#{Time.now.to_i}.com." }

      context "the aws_route53_hosted_zone resource" do
        context ":create" do
          it "creates a hosted zone without attributes" do
            expect_recipe {
              aws_route53_hosted_zone zone_name do
                action :create
              end
            }.to create_an_aws_route53_hosted_zone(zone_name).and be_idempotent
          end

          it "creates a hosted zone with attributes" do
            test_comment = "Test comment for spec."

            expect_recipe {
              aws_route53_hosted_zone zone_name do
                action :create
                comment test_comment
              end
            }.to create_an_aws_route53_hosted_zone(zone_name,
                                                   config: { comment: test_comment }
                                                   ).and be_idempotent
          end
        end

        context ":purge" do
          it "creates a hosted zone with RecordSets and purges it" do
            expect_recipe {
              aws_route53_hosted_zone zone_name do
                action :create
                record_sets {
                  aws_route53_record_set "some-hostname CNAME" do
                    rr_name "some-api-host.example.com"
                    type "CNAME"
                    ttl 3600
                    resource_records [{ value: "some-other-host.example.com."}]
                  end

                  # Chefception: because we're doing `instance_eval` and not `eval`, the `zone_name` let-var
                  # is not available inside the aws_route53_record_set, which is...less useful.
                  # TODO: investigate if this has real-world consequences, or is just inconvenient for
                  # testing.

                  # aws_route53_record_set "something A" do
                  #   rr_name "some-api-host.#{zone_name}"
                  #   type "A"
                  #   ttl 3600
                  #   resource_records [
                  #     { value: "141.222.2.2"   },
                  #     { value: "192.168.10.89" },
                  #   ]
                  # end
                }
              end
            }.to create_an_aws_route53_hosted_zone(zone_name)        #.and be_idempotent
          end
        end
      end
    end
  end
end

require 'spec_helper'

describe Chef::Resource::AwsRoute53HostedZone do
  extend AWSSupport

  when_the_chef_12_server "exists", organization: 'foo', server_scope: :context do
    with_aws "when connected to AWS" do


      context "aws_route53_hosted_zone" do
        let(:zone_name) { "aws-spec-#{Time.now.to_i}.com." }

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

        context "RecordSets" do

          # our work to access let-vars inside expect_recipe/_converge blocks does not apply to using them
          # inside the `record_sets` block, which gets instance_eval'd in the aws_route53_hosted_zone resource.

          it "crashes on duplicate [name, type] RecordSets" do
            expect_converge {
              aws_route53_hosted_zone "chasm.com" do
                action :create

                record_sets {
                  aws_route53_record_set "wooster1" do
                    rr_name "wooster.chasm.com"
                    type "CNAME"
                    ttl 300
                  end
                  aws_route53_record_set "wooster2" do
                    rr_name "wooster.chasm.com"
                    type "CNAME"
                    ttl 3600
                  end
                }
              end
            }.to raise_error(Chef::Exceptions::ValidationFailed, /Duplicate RecordSet found in resource/)
          end

          it "crashes on a RecordSet with a non-:nothing action" do
            expect_converge {
              aws_route53_hosted_zone zone_name do
                action :create

                record_sets {
                  aws_route53_record_set "wooster1" do
                    action :create
                    rr_name "wooster.example.com"
                    type "CNAME"
                    ttl 300
                  end
                }
              end
            }.to raise_error(Chef::Exceptions::ValidationFailed, /Option action must be equal to one of/)
          end
        end

        it "creates a hosted zone with RecordSets and purges it" do
          # because we're doing `instance_eval` and not `eval`, the `zone_name` let-var is not available
          # inside the aws_route53_record_set.

          expect_recipe {
            aws_route53_hosted_zone "feegle.com" do
              action :create
              record_sets {
                aws_route53_record_set "some-hostname CNAME" do
                  rr_name "some-api-host.feegle.com"
                  type "CNAME"
                  ttl 3600
                  resource_records [{ value: "some-other-host"}]
                end


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
          }.to create_an_aws_route53_hosted_zone("feegle.com")        #.and be_idempotent
        end
      end
    end
  end
end

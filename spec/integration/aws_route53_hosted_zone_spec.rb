require 'spec_helper'

describe Chef::Resource::AwsRoute53HostedZone do
  extend AWSSupport

  when_the_chef_12_server "exists", organization: 'foo', server_scope: :context do
    with_aws "when connected to AWS" do

      # even though these resources are demonstrably convergent, `be_idempotent` fails, including when
      # `update_aws_object` is nothing but an empty `converge_by` block. suggestions welcome.
      context "aws_route53_hosted_zone" do
        let(:zone_name) { "aws-spec-#{Time.now.to_i}.com" }

        context ":create" do
          it "creates a hosted zone without attributes" do
            expect_recipe {
              aws_route53_hosted_zone zone_name do
                action :create
              end
            }.to create_an_aws_route53_hosted_zone(zone_name)
          end

          it "creates a hosted zone with attributes" do
            test_comment = "Test comment for spec."

            expect_recipe {
              aws_route53_hosted_zone zone_name do
                action :create
                comment test_comment
              end
            }.to create_an_aws_route53_hosted_zone(zone_name,
                                                   config: { comment: test_comment })
          end

          # we don't want to go overboard testing all our validations, but this is the one that can cause the
          # most difficult user confusion, and AWS won't catch it.
          it "crashes if the zone name has a trailing dot" do
            expect_converge {
              aws_route53_hosted_zone "#{zone_name}."
            }.to raise_error(Chef::Exceptions::ValidationFailed, /domain name cannot end with a dot/)
          end

          it "updates the zone comment"
        end

        context "RecordSets" do
          it "crashes on duplicate [name, type] RecordSets" do
            skip "invalid test, needs to crash on duplicate RR names, regardless of type"
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

          # normally wouldn't bother with this, and maybe even here we shouldn't.
          it "crashes on a RecordSet with an invalid action" do
            expect_converge {
              aws_route53_hosted_zone zone_name do
                record_sets {
                  aws_route53_record_set "wooster1" do
                    action :invoke
                    rr_name "wooster.example.com"
                    type "CNAME"
                    ttl 300
                  end
                }
              end
            }.to raise_error(Chef::Exceptions::ValidationFailed, /Option action must be equal to one of/)
          end
        end

        it "creates a hosted zone with a RecordSet" do
          expected_sdk_rr = {
            name: "some-api-host.feegle.com.",  # AWS adds the trailing dot.
            type: "CNAME",
            ttl: 3600,
            resource_records: [{ value: "some-other-host"}],
          }
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
              }
            end
          }.to create_an_aws_route53_hosted_zone("feegle.com",
                                                 resource_record_sets: [{}, {}, expected_sdk_rr])
          # the empty {} acts as a wildcard, and all zones have SOA and NS records we want to skip.
        end

        it "creates and updates a RecordSet" do
          expected_sdk_rr = {
            name: "some-api-host.feegle.com.",  # AWS adds the trailing dot.
            type: "CNAME",
            ttl: 1800,
            resource_records: [{ value: "far-side-of-the-world"}],
          }
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
              }
            end

            aws_route53_hosted_zone "feegle.com" do
              action :create
              record_sets {
                aws_route53_record_set "some-hostname CNAME" do
                  rr_name "some-api-host.feegle.com"
                  type "CNAME"
                  ttl 1800
                  resource_records [{ value: "far-side-of-the-world"}]
                end
              }
            end
          }.to create_an_aws_route53_hosted_zone("feegle.com",
                                                 resource_record_sets: [{}, {}, expected_sdk_rr])
        end

        it "creates and deletes a RecordSet" do

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
              }
            end

            aws_route53_hosted_zone "feegle.com" do
              action :create
              record_sets {
                aws_route53_record_set "some-hostname CNAME" do
                  action :destroy
                  rr_name "some-api-host.feegle.com"
                  type "CNAME"
                  ttl 3600
                  resource_records [{ value: "some-other-host"}]
                end
              }
            end
          }.to create_an_aws_route53_hosted_zone("feegle.com",
                                                 resource_record_sets: [{}, {}])
        end

        it "raises the AWS exception when trying to delete a record using mismatched values"

        it "works with RR types besides CNAME and A"

        it "handles multiple actions correctly, assuming that even makes sense"

        it "overrides the :name attribute with :rr_name"

        it "applies the :name validations to :rr_name"
      end
    end
  end
end

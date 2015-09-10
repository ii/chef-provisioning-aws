require 'aws-sdk'
require 'securerandom'

client = Aws::Route53::Client.new

zone_name = "cdoherty-aws-development-delete-me.com."
zone_id = "/hostedzone/Z3AK521MXMQ1L6"

rs = [
  {
      action: "CREATE", # required, accepts CREATE, DELETE, UPSERT
      resource_record_set: { # required
        name: "some-api-host.#{zone_name}.", # required
        type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
        # set_identifier: SecureRandom.uuid.upcase,
        # weight: 1,
        # region: "us-east-1", # accepts us-east-1, us-west-1, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, sa-east-1, cn-north-1
        # failover: "PRIMARY", # accepts PRIMARY, SECONDARY
        # ttl: 1,
        resource_records: [
          {
            value: "some-other-host.example.com.", # required
          },
        ],
        # alias_target: {
        #   hosted_zone_id: "ResourceId", # required
        #   dns_name: "DNSName", # required
        #   evaluate_target_health: true, # required
        # },
        # health_check_id: "HealthCheckId",
      },
    },
  ]

params = {
  hosted_zone_id: zone_id,
  change_batch: {
    comment: "Change the RRs",
    changes: rs,
  }
}

result = client.change_resource_record_sets(params)
require 'pry'; binding.pry

require 'aws-sdk'
require 'securerandom'

client = Aws::Route53::Client.new

zone_name = "cdoherty-aws-development-delete-me.com."
zone_id = "/hostedzone/Z3AK521MXMQ1L6"

rs = [
  {
    action: "CREATE", # required, accepts CREATE, DELETE, UPSERT
    resource_record_set: { # required
      name: "from-script2.#{zone_name}", # required
      type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA,
      ttl: 3600,
      # failover: "PRIMARY",
      resource_records: [{ value: "some-other-host.example.com." }],
      # resource_records: [{ value: "192.168.1.5" }],
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

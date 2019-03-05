module Terraforming
  module Resource
    class VPC
      include Terraforming::Util

      def self.tf(ids: [], client: Aws::EC2::Client.new)
        self.new(client, ids).tf
      end

      def self.tfstate(ids: [], client: Aws::EC2::Client.new)
        self.new(client, ids).tfstate
      end

      def self.name(id, client: Aws::EC2::Client.new)
        self.new(client, []).name(id)
      end

      def initialize(client, ids)
        @client = client
        @ids = ids
      end

      def tf
        apply_template(@client, "tf/vpc")
      end

      def tfstate
        vpcs.inject({}) do |resources, vpc|
          attributes = {
            "cidr_block" => vpc.cidr_block,
            "enable_dns_hostnames" => enable_dns_hostnames?(vpc).to_s,
            "enable_dns_support" => enable_dns_support?(vpc).to_s,
            "id" => vpc.vpc_id,
            "instance_tenancy" => vpc.instance_tenancy,
            "tags.#" => vpc.tags.length.to_s,
          }
          resources["aws_vpc.#{module_name_of(vpc)}"] = {
            "type" => "aws_vpc",
            "primary" => {
              "id" => vpc.vpc_id,
              "attributes" => attributes
            }
          }

          resources
        end
      end

      def name(id)
        v = vpcs.select { |e| e.vpc_id==id }
        if v.length > 0
          "${aws_vpc.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def enable_dns_hostnames?(vpc)
        vpc_attribute(vpc, :enableDnsHostnames).enable_dns_hostnames.value
      end

      def enable_dns_support?(vpc)
        vpc_attribute(vpc, :enableDnsSupport).enable_dns_support.value
      end

      def module_name_of(vpc)
        normalize_module_name(name_from_tag(vpc, vpc.vpc_id))
      end

      def vpcs
        return @client.describe_vpcs.map(&:vpcs).flatten if @ids.empty?
        @client.describe_vpcs.map(&:vpcs).flatten.select{ |e| @ids.include?(e.vpc_id) }
      end

      def vpc_attribute(vpc, attribute)
        @client.describe_vpc_attribute(vpc_id: vpc.vpc_id, attribute: attribute)
      end
    end
  end
end

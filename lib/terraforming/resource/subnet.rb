module Terraforming
  module Resource
    class Subnet
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
        apply_template(@client, "tf/subnet")
      end

      def tfstate
        subnets.inject({}) do |resources, subnet|
          attributes = {
            "availability_zone" => subnet.availability_zone,
            "cidr_block" => subnet.cidr_block,
            "id" => subnet.subnet_id,
            "map_public_ip_on_launch" => subnet.map_public_ip_on_launch.to_s,
            "tags.#" => subnet.tags.length.to_s,
            "vpc_id" => subnet.vpc_id,
          }
          resources["aws_subnet.#{module_name_of(subnet)}"] = {
            "type" => "aws_subnet",
            "primary" => {
              "id" => subnet.subnet_id,
              "attributes" => attributes
            }
          }

          resources
        end
      end

      def name(id)
        v = subnets.select { |e| e.subnet_id==id }
        if v.length > 0
          "${aws_subnet.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def subnets
        return @client.describe_subnets.map(&:subnets).flatten if @ids.empty?
        @client.describe_subnets.map(&:subnets).flatten.select{ |e| @ids.include?(e.vpc_id) }
      end

      def module_name_of(subnet)
        normalize_module_name("#{subnet.subnet_id}-#{name_from_tag(subnet, subnet.subnet_id)}")
      end
    end
  end
end

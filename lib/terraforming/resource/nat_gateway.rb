module Terraforming
  module Resource
    class NATGateway
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
        apply_template(@client, "tf/nat_gateway")
      end

      def tfstate
        nat_gateways.inject({}) do |resources, nat_gateway|
          next resources if nat_gateway.nat_gateway_addresses.empty?

          attributes = {
            "id" => nat_gateway.nat_gateway_id,
            "allocation_id" => nat_gateway.nat_gateway_addresses[0].allocation_id,
            "subnet_id" => nat_gateway.subnet_id,
            "network_inferface_id" => nat_gateway.nat_gateway_addresses[0].network_interface_id,
            "private_ip" => nat_gateway.nat_gateway_addresses[0].private_ip,
            "public_ip" => nat_gateway.nat_gateway_addresses[0].public_ip,
          }
          resources["aws_nat_gateway.#{module_name_of(nat_gateway)}"] = {
            "type" => "aws_nat_gateway",
            "primary" => {
              "id"         => nat_gateway.nat_gateway_id,
              "attributes" => attributes
            }
          }

          resources
        end
      end

      def name(id)
        v = nat_gateways.select { |e| e.nat_gateway_id==id }
        if v.length > 0
          "${aws_nat_gateway.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def nat_gateways
        return @client.describe_nat_gateways.nat_gateways if @ids.empty?
        @client.describe_nat_gateways.nat_gateways.select{ |e| @ids.include?(e.nat_gateway_id) }
      end

      def module_name_of(nat_gateway)
        normalize_module_name(nat_gateway.nat_gateway_id)
      end
    end
  end
end

module Terraforming
  module Resource
    class InternetGateway
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
        apply_template(@client, "tf/internet_gateway")
      end

      def tfstate
        internet_gateways.inject({}) do |resources, internet_gateway|
          next resources if internet_gateway.attachments.empty?

          attributes = {
            "id"     => internet_gateway.internet_gateway_id,
            "vpc_id" => internet_gateway.attachments[0].vpc_id,
            "tags.#" => internet_gateway.tags.length.to_s,
          }
          resources["aws_internet_gateway.#{module_name_of(internet_gateway)}"] = {
            "type" => "aws_internet_gateway",
            "primary" => {
              "id"         => internet_gateway.internet_gateway_id,
              "attributes" => attributes
            }
          }

          resources
        end
      end

      def name(id)
        v = internet_gateways.select { |e| e.internet_gateway_id==id }
        if v.length > 0
          "${aws_internet_gateway.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def internet_gateways
        return @client.describe_internet_gateways.map(&:internet_gateways).flatten if @ids.empty?
        @client.describe_internet_gateways.map(&:internet_gateways).flatten.select{ |e| @ids.include?(e.internet_gateway_id) }
      end

      def module_name_of(internet_gateway)
        normalize_module_name(name_from_tag(internet_gateway, internet_gateway.internet_gateway_id))
      end
    end
  end
end

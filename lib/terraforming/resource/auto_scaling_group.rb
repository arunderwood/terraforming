module Terraforming
  module Resource
    class AutoScalingGroup
      include Terraforming::Util

      def self.tf(ids: [], client: Aws::AutoScaling::Client.new)
        self.new(client, ids).tf
      end

      def self.tfstate(ids: [], client: Aws::AutoScaling::Client.new)
        self.new(client, ids).tfstate
      end

      def self.name(id, client: Aws::AutoScaling::Client.new)
        self.new(client, []).name(id)
      end

      def initialize(client, ids)
        @client = client
        @ids = ids
      end

      def tf
        apply_template(@client, "tf/auto_scaling_group")
      end

      def tfstate
        auto_scaling_groups.inject({}) do |resources, group|
          vpc_zone_specified = vpc_zone_specified?(group)

          attributes = {
            "availability_zones.#" => vpc_zone_specified ? "0" : group.availability_zones.length.to_s,
            "default_cooldown" => "300",
            "desired_capacity" => group.desired_capacity.to_s,
            "health_check_grace_period" => group.health_check_grace_period.to_s,
            "health_check_type" => group.health_check_type,
            "id" => group.auto_scaling_group_name,
            "launch_configuration" => group.launch_configuration_name,
            "load_balancers.#" => "0",
            "max_size" => group.max_size.to_s,
            "min_size" => group.min_size.to_s,
            "name" => group.auto_scaling_group_name,
            "tag.#" => group.tags.length.to_s,
            "termination_policies.#" => "0",
            "vpc_zone_identifier.#" => vpc_zone_specified ? vpc_zone_identifier_of(group).length.to_s : "0",
            "force_delete" => "false",
            "metrics_granularity" => "1Minute",
            "wait_for_capacity_timeout" => "10m",
          }

          group.tags.each do |tag|
            hashcode = tag_hashcode_of(tag)
            attributes.merge!({
              "tag.#{hashcode}.key" => tag.key,
              "tag.#{hashcode}.propagate_at_launch" => tag.propagate_at_launch.to_s,
              "tag.#{hashcode}.value" => tag.value,
            })
          end

          resources["aws_autoscaling_group.#{module_name_of(group)}"] = {
            "type" => "aws_autoscaling_group",
            "primary" => {
              "id" => group.auto_scaling_group_name,
              "attributes" => attributes,
              "meta" => {
                "schema_version" => "1"
              }
            }
          }

          resources
        end
      end

      def name(id)
        v = auto_scaling_groups.select { |e| e.auto_scaling_group_name==id }
        if v.length > 0
          "${aws_autoscaling_group.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def auto_scaling_groups
        return @client.describe_auto_scaling_groups.map(&:auto_scaling_groups).flatten if @ids.empty?
        @client.describe_auto_scaling_groups.map(&:auto_scaling_groups).flatten.select{ |e| @ids.include?(e.auto_scaling_group_name) }
      end

      def module_name_of(group)
        normalize_module_name(group.auto_scaling_group_name)
      end

      def tag_hashcode_of(tag)
        Zlib.crc32("#{tag.key}-#{tag.value}-#{tag.propagate_at_launch}-")
      end

      def vpc_zone_identifier_of(group)
        group.vpc_zone_identifier.split(",")
      end

      def vpc_zone_specified?(group)
        group.vpc_zone_identifier && !vpc_zone_identifier_of(group).empty?
      end
    end
  end
end

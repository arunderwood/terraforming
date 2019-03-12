module Terraforming
  module Resource
    class AutoScalingSchedule
      include Terraforming::Util

      def self.tf(ids: [], client: Aws::AutoScaling::Client.new)
        self.new(client, ids).tf
      end

      def self.tfstate(ids: [], client: Aws::AutoScaling::Client.new)
        self.new(client, ids).tfstate
      end

      def initialize(client, ids)
        @client = client
        @ids = ids
      end

      def tf
        apply_template(@client, "tf/auto_scaling_schedule")
      end

      def tfstate
        auto_scaling_schedules.inject({}) do |resources, schedule|

          attributes = {
            "autoscaling_group_name" => schedule.auto_scaling_group_name,
            "id" => schedule.scheduled_action_name,
            "scheduled_action_name" => schedule.scheduled_action_name,
          }

          resources["aws_autoscaling_schedule.#{module_name_of(schedule)}"] = {
            "type" => "aws_autoscaling_schedule",
            "primary" => {
              "id" => schedule.scheduled_action_name,
              "attributes" => attributes
            }
          }
          resources
        end
      end

      private

      def auto_scaling_schedules
        return @client.describe_scheduled_actions.map(&:scheduled_update_group_actions).flatten if @ids.empty?
        @client.describe_scheduled_actions.map(&:scheduled_update_group_actions).flatten.select{ |e| @ids.include?(e.scheduled_action_name) }
      end

      def module_name_of(schedule)
        normalize_module_name("#{schedule.auto_scaling_group_name}-#{schedule.scheduled_action_name}")
      end

    end
  end
end

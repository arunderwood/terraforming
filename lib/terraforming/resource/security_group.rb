module Terraforming
  module Resource
    class SecurityGroup
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
        apply_template(@client, "tf/security_group")
      end

      def tfstate
        security_groups.inject({}) do |resources, security_group|
          attributes = {
            "description" => security_group.description,
            "id" => security_group.group_id,
            "name" => security_group.group_name,
            "owner_id" => security_group.owner_id,
            "vpc_id" => security_group.vpc_id || "",
          }

          attributes.merge!(tags_attributes_of(security_group))

          resources["aws_security_group.#{module_name_of(security_group)}"] = {
            "type" => "aws_security_group",
            "primary" => {
              "id" => security_group.group_id,
              "attributes" => attributes
            }
          }

          resources.merge!(security_group_rule(security_group))

          resources
        end
      end

      def name(id)
        v = security_groups.select { |e| e.group_id==id }
        if v.length > 0
          "${aws_security_group.#{module_name_of(v[0])}.id}"
        else
          id
        end
      end

      private

      def security_group_rule(security_group)
        ingresses = dedup_permissions(security_group.ip_permissions, security_group.group_id)
        egresses = dedup_permissions(security_group.ip_permissions_egress, security_group.group_id)
        rule_count = 0
        resources = {}

        ingresses.each do |permission|
          resources.merge!(permission_state_of(security_group, permission, rule_count, "ingress"))
          rule_count += 1
        end

        egresses.each do |permission|
          resources.merge!(permission_state_of(security_group, permission, rule_count, "egress"))
          rule_count += 1
        end

        resources
      end

      def permission_state_of(security_group, permission, count, type)
        resources = {}
        resources["aws_security_group_rule.#{module_name_of(security_group)}#{count>0?"-#{count}":''}"] = {
          "type" => "aws_security_group_rule",
          "primary" => {
            "id" => "sgrule-#{permission_hashcode_of(security_group, permission)}",
            "attributes" => permission_attributes_of(security_group, permission, type)
          }
        }
        resources
      end

      def egress_rules(security_group)
        egresses = dedup_permissions(security_group.ip_permissions_egress, security_group.group_id)
        attributes = { "egress.#" => egresses.length.to_s }

        egresses.each do |permission|
          attributes.merge!(permission_attributes_of(security_group, permission, "egress"))
        end

        attributes
      end

      def group_hashcode_of(group)
        Zlib.crc32(group)
      end

      def module_name_of(security_group)
        if security_group.vpc_id.nil?
          normalize_module_name(security_group.group_name.to_s)
        else
          normalize_module_name("#{security_group.vpc_id}-#{security_group.group_name}")
        end
      end

      def permission_attributes_of(security_group, permission, type)
        hashcode = permission_hashcode_of(security_group, permission)
        security_groups = security_groups_in(permission, security_group).reject do |identifier|
          [security_group.group_name, security_group.group_id].include?(identifier)
        end

        attributes = {
          "type" => type,
          "from_port" => (permission.from_port || 0).to_s,
          "to_port" => (permission.to_port || 0).to_s,
          "protocol" => permission.ip_protocol,
          "cidr_blocks.#" => permission.ip_ranges.length.to_s,
          "prefix_list_ids.#" => permission.prefix_list_ids.length.to_s,
          "self" => self_referenced_permission?(security_group, permission).to_s,
          "security_group_id" => security_group.group_id,
        }

        permission.ip_ranges.each_with_index do |range, index|
          attributes["cidr_blocks.#{index}"] = range.cidr_ip
        end

        permission.prefix_list_ids.each_with_index do |prefix_list, index|
          attributes["prefix_list_ids.#{index}"] = prefix_list.prefix_list_id
        end

        attributes
      end

      def dedup_permissions(permissions, group_id)
        group_permissions(permissions).inject([]) do |result, (_, perms)|
          group_ids = perms.map(&:user_id_group_pairs).flatten.map(&:group_id)

          if group_ids.length == 1 && group_ids.first == group_id
            result << merge_permissions(perms)
          else
            result.concat(perms)
          end

          result
        end
      end

      def group_permissions(permissions)
        permissions.group_by { |permission| [permission.ip_protocol, permission.to_port, permission.from_port] }
      end

      def merge_permissions(permissions)
        master_permission = permissions.pop

        permissions.each do |permission|
          master_permission.user_id_group_pairs.concat(permission.user_id_group_pairs)
          master_permission.ip_ranges.concat(permission.ip_ranges)
        end

        master_permission
      end

      def permission_hashcode_of(security_group, permission)
        string =
          "#{permission.from_port || 0}-" <<
          "#{permission.to_port || 0}-" <<
          "#{permission.ip_protocol}-" <<
          "#{self_referenced_permission?(security_group, permission)}-"

        permission.ip_ranges.each { |range| string << "#{range.cidr_ip}-" }
        security_groups_in(permission, security_group).each { |group| string << "#{group}-" }

        Zlib.crc32(string)
      end

      def self_referenced_permission?(security_group, permission)
        (security_groups_in(permission, security_group) & [security_group.group_id, security_group.group_name]).any?
      end

      def security_groups
        return @client.describe_security_groups.map(&:security_groups).flatten if @ids.empty?
        @client.describe_security_groups.map(&:security_groups).flatten.select{ |e| @ids.include?(e.group_id) }
      end

      def security_groups_in(permission, security_group)
        permission.user_id_group_pairs.map do |range|
          # EC2-Classic, same account
          if security_group.owner_id == range.user_id && !range.group_name.nil?
            range.group_name
          # VPC
          elsif security_group.owner_id == range.user_id && range.group_name.nil?
            range.group_id
          # EC2-Classic, other account
          else
            "#{range.user_id}/#{range.group_name || range.group_id}"
          end
        end
      end

      def tags_attributes_of(security_group)
        tags = security_group.tags
        attributes = { "tags.#" => tags.length.to_s }
        tags.each { |tag| attributes["tags.#{tag.key}"] = tag.value }
        attributes
      end
    end
  end
end

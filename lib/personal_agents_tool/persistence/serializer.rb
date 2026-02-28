# frozen_string_literal: true
# typed: strict

require "json"
require "sorbet-runtime"

module PersonalAgentsTool
  module Persistence
    class Serializer
      extend T::Sig

      sig { params(struct: T::Struct).returns(T::Hash[String, T.untyped]) }
      def self.serialize(struct)
        result = T.let({}, T::Hash[String, T.untyped])

        struct.class.props.each_key do |prop_name|
          value = struct.send(prop_name)
          result[prop_name.to_s] = serialize_value(value)
        end

        result
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def self.serialize_value(value)
        case value
        when T::Struct
          serialize(value)
        when Array
          value.map { |v| serialize_value(v) }
        when Hash
          value.transform_keys(&:to_s).transform_values { |v| serialize_value(v) }
        else
          value
        end
      end

      sig { params(hash: T::Hash[String, T.untyped], struct_class: T.class_of(T::Struct)).returns(T::Struct) }
      def self.deserialize(hash, struct_class)
        kwargs = T.let({}, T::Hash[Symbol, T.untyped])

        struct_class.props.each do |prop_name, prop_info|
          str_key = prop_name.to_s
          next unless hash.key?(str_key)

          value = hash[str_key]
          kwargs[prop_name] = deserialize_value(value, prop_info[:type])
        end

        struct_class.new(**kwargs)
      end

      sig { params(value: T.untyped, type: T.untyped).returns(T.untyped) }
      def self.deserialize_value(value, type)
        return value if value.nil?

        raw_type = if type.respond_to?(:raw_type)
                     type.raw_type
                   elsif type.is_a?(Class)
                     type
                   end

        if raw_type && raw_type < T::Struct && value.is_a?(Hash)
          deserialize(value, raw_type)
        else
          value
        end
      end

      sig { params(struct: T::Struct).returns(String) }
      def self.to_json(struct)
        JSON.pretty_generate(serialize(struct))
      end

      sig { params(json_string: String, struct_class: T.class_of(T::Struct)).returns(T::Struct) }
      def self.from_json(json_string, struct_class)
        hash = JSON.parse(json_string)
        deserialize(hash, struct_class)
      end

      private_class_method :serialize_value, :deserialize_value
    end
  end
end

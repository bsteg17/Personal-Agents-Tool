# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Agent
    class Base
      extend T::Sig

      class << self
        extend T::Sig

        sig { params(schema_class: T.class_of(T::Struct)).void }
        def input(schema_class)
          @input_schema = schema_class
        end

        sig { params(schema_class: T.class_of(T::Struct)).void }
        def output(schema_class)
          @output_schema = schema_class
        end

        sig { returns(T.nilable(T.class_of(T::Struct))) }
        def input_schema
          @input_schema
        end

        sig { returns(T.nilable(T.class_of(T::Struct))) }
        def output_schema
          @output_schema
        end

        sig { params(name: Symbol, tool_class: T.class_of(Tool::Base)).void }
        def tool(name, tool_class)
          @tools ||= T.let({}, T.nilable(T::Hash[Symbol, T.class_of(Tool::Base)]))
          @tools[name] = tool_class
        end

        sig { returns(T::Hash[Symbol, T.class_of(Tool::Base)]) }
        def tools
          @tools || {}
        end

        sig { params(name: T.nilable(String)).returns(T.nilable(String)) }
        def model(name = nil)
          if name
            @model = name
          end
          @model
        end

        sig { params(name: T.nilable(String)).returns(T.nilable(String)) }
        def provider(name = nil)
          if name
            @provider = name
          end
          @provider
        end
      end

      sig { params(llm: T.nilable(LLM::Client)).void }
      def initialize(llm: nil)
        @llm = T.let(llm, T.nilable(LLM::Client))
      end

      sig { returns(T.nilable(LLM::Client)) }
      attr_reader :llm

      sig { params(input_data: T::Struct).returns(Result) }
      def execute(input_data)
        input_schema = self.class.input_schema
        output_schema = self.class.output_schema

        raise InvalidInputError, "No input schema declared on #{self.class}" if input_schema.nil?
        raise InvalidOutputError, "No output schema declared on #{self.class}" if output_schema.nil?

        unless input_data.is_a?(input_schema)
          raise InvalidInputError,
            "Expected #{input_schema}, got #{input_data.class}"
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output_data = call(input_data)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        unless output_data.is_a?(output_schema)
          raise InvalidOutputError,
            "Expected #{output_schema}, got #{output_data.class}"
        end

        Result.new(
          output: output_data,
          agent_class: self.class,
          duration: duration
        )
      end

      sig { params(_input: T::Struct).returns(T::Struct) }
      def call(_input)
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end

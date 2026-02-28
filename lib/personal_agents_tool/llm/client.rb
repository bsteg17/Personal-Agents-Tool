# frozen_string_literal: true
# typed: strict

require "json"
require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    class Client
      extend T::Sig

      PROVIDER_MAP = T.let({
        "claude" => Providers::Claude,
        "openai" => Providers::OpenAI,
        "gemini" => Providers::Gemini,
      }.freeze, T::Hash[String, T.class_of(Providers::Base)])

      sig do
        params(
          provider: String,
          model: String,
          max_retries: Integer
        ).void
      end
      def initialize(provider:, model:, max_retries: 3)
        provider_class = PROVIDER_MAP[provider]
        raise UnknownProviderError, "Unknown provider: #{provider}" if provider_class.nil?

        @provider = T.let(provider_class.new, Providers::Base)
        @model = T.let(model, String)
        @max_retries = T.let(max_retries, Integer)
      end

      sig { returns(Providers::Base) }
      attr_reader :provider

      sig { returns(String) }
      attr_reader :model

      sig { returns(Integer) }
      attr_reader :max_retries

      sig do
        params(
          prompt: String,
          schema: T.nilable(T.class_of(T::Struct)),
          system: T.nilable(String),
          tools: T.nilable(T::Hash[Symbol, T.class_of(Tool::Base)])
        ).returns(T.any(String, T::Struct))
      end
      def chat(prompt:, schema: nil, system: nil, tools: nil)
        messages = T.let([], T::Array[T::Hash[Symbol, String]])
        messages << { role: "system", content: system } if system
        messages << { role: "user", content: prompt }

        if tools && schema.nil?
          chat_with_tools(messages: messages, tools: tools)
        elsif schema
          chat_with_schema(messages: messages, schema: schema, tools: tools)
        else
          response = @provider.chat(messages: messages, model: @model)
          T.must(response.content)
        end
      end

      private

      sig do
        params(
          messages: T::Array[T::Hash[Symbol, String]],
          tools: T::Hash[Symbol, T.class_of(Tool::Base)]
        ).returns(String)
      end
      def chat_with_tools(messages:, tools:)
        loop do
          response = @provider.chat(messages: messages, model: @model, tools: tools)

          if response.tool_calls.empty?
            return T.must(response.content)
          end

          messages << { role: "assistant", content: response.content || "" }

          response.tool_calls.each do |tool_call|
            tool_class = tools[tool_call.name]
            result = T.must(tool_class).execute(tool_call.arguments)
            messages << { role: "tool", content: result.to_s }
          end
        end
      end

      sig do
        params(
          messages: T::Array[T::Hash[Symbol, String]],
          schema: T.class_of(T::Struct),
          tools: T.nilable(T::Hash[Symbol, T.class_of(Tool::Base)])
        ).returns(T::Struct)
      end
      def chat_with_schema(messages:, schema:, tools: nil)
        attempts = 0

        loop do
          response = @provider.chat(messages: messages, model: @model, tools: tools)
          content = T.must(response.content)

          begin
            parsed = JSON.parse(content)
            symbolized = parsed.transform_keys(&:to_sym)
            return schema.new(**symbolized)
          rescue StandardError => e
            attempts += 1
            if attempts >= @max_retries
              raise ParseError, "Failed to parse structured output after #{@max_retries} retries: #{e.message}"
            end

            messages << { role: "assistant", content: content }
            messages << { role: "user", content: "Your response was not valid JSON matching the expected schema. Error: #{e.message}. Please try again." }
          end
        end
      end
    end
  end
end

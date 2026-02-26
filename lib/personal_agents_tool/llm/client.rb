# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    class Client
      extend T::Sig

      sig do
        params(
          prompt: String,
          schema: T.nilable(T.class_of(T::Struct)),
          system: T.nilable(String),
          tools: T.nilable(T::Hash[Symbol, T.untyped])
        ).returns(T.untyped)
      end
      def chat(prompt:, schema: nil, system: nil, tools: nil)
        raise ::NotImplementedError, "LLM::Client#chat is not yet implemented"
      end
    end
  end
end

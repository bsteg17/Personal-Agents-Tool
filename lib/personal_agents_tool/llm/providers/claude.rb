# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    module Providers
      class Claude < Base
        extend T::Sig

        sig do
          override.params(
            messages: T::Array[T::Hash[Symbol, String]],
            model: String,
            tools: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(PersonalAgentsTool::LLM::Response)
        end
        def chat(messages:, model:, tools: nil)
          raise NotImplementedError, "Claude provider HTTP calls not yet implemented"
        end
      end
    end
  end
end

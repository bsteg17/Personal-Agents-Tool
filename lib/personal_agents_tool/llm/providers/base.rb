# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    module Providers
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig do
          abstract.params(
            messages: T::Array[T::Hash[Symbol, String]],
            model: String,
            tools: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(PersonalAgentsTool::LLM::Response)
        end
        def chat(messages:, model:, tools: nil)
        end
      end
    end
  end
end

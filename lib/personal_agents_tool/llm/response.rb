# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    class Response < T::Struct
      const :content, T.nilable(String)
      const :tool_calls, T::Array[T::Hash[Symbol, T.untyped]], default: []
    end
  end
end

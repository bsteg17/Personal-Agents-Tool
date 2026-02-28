# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Persistence
    class StepStatus < T::Struct
      const :status, String
      const :retry_count, Integer, default: 0
      const :error, T.nilable(String)
      const :error_class, T.nilable(String)
      const :started_at, T.nilable(String)
      const :completed_at, T.nilable(String)
      const :duration, T.nilable(Float)
      const :retries, T::Array[T::Hash[String, T.untyped]], default: []
    end
  end
end

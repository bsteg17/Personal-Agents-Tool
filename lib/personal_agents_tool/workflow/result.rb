# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Workflow
    class Result < T::Struct
      const :success, T::Boolean
      const :step_results, T::Hash[Symbol, Agent::Result]
      const :failed_step, T.nilable(Symbol)
      const :error, T.nilable(String)
      const :error_details, T.nilable(String)
      const :duration, Float
    end
  end
end

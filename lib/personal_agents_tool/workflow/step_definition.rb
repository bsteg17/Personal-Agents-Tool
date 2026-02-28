# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Workflow
    class StepDefinition < T::Struct
      const :name, Symbol
      const :agent_class, T.class_of(Agent::Base)
      const :after, T::Array[Symbol], default: []
      const :retries, T.nilable(Integer), default: nil
    end
  end
end

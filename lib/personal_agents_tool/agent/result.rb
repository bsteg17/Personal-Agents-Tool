# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Agent
    class Result < T::Struct
      const :output, T.untyped
      const :agent_class, T.class_of(PersonalAgentsTool::Agent::Base)
      const :duration, T.nilable(Float)
    end
  end
end

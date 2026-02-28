# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Workflow
    class MergedInput < T::Struct
      const :outputs, T::Hash[Symbol, T::Struct]
    end
  end
end

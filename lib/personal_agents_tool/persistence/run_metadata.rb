# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Persistence
    class RunMetadata < T::Struct
      const :workflow_name, String
      const :status, String
      const :steps, T::Array[String]
      const :created_at, String
      const :updated_at, String
      const :config, T::Hash[String, T.untyped], default: {}
    end
  end
end

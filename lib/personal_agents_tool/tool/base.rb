# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Tool
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.params(args: T.untyped).returns(String) }
      def self.execute(args); end
    end
  end
end

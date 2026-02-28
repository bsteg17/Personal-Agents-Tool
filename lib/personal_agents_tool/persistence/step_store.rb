# frozen_string_literal: true
# typed: strict

require "json"
require "sorbet-runtime"

module PersonalAgentsTool
  module Persistence
    class StepStore
      extend T::Sig

      sig { params(step_dir: String).void }
      def initialize(step_dir)
        @step_dir = T.let(step_dir, String)
      end

      sig { returns(String) }
      attr_reader :step_dir

      sig { params(input: T::Struct).void }
      def write_input(input)
        write_file("input.json", Serializer.to_json(input))
      end

      sig { params(struct_class: T.class_of(T::Struct)).returns(T::Struct) }
      def read_input(struct_class)
        json = read_file("input.json")
        Serializer.from_json(json, struct_class)
      end

      sig { params(output: T::Struct).void }
      def write_output(output)
        write_file("output.json", Serializer.to_json(output))
      end

      sig { params(struct_class: T.class_of(T::Struct)).returns(T::Struct) }
      def read_output(struct_class)
        json = read_file("output.json")
        Serializer.from_json(json, struct_class)
      end

      sig { params(status: StepStatus).void }
      def write_status(status)
        write_file("status.json", Serializer.to_json(status))
      end

      sig { returns(StepStatus) }
      def read_status
        json = read_file("status.json")
        T.cast(Serializer.from_json(json, StepStatus), StepStatus)
      end

      sig { returns(T::Boolean) }
      def output_exists?
        File.exist?(file_path("output.json"))
      end

      sig { returns(T::Boolean) }
      def status_exists?
        File.exist?(file_path("status.json"))
      end

      private

      sig { params(filename: String, content: String).void }
      def write_file(filename, content)
        File.write(file_path(filename), content)
      end

      sig { params(filename: String).returns(String) }
      def read_file(filename)
        path = file_path(filename)
        raise RunNotFoundError, "File not found: #{path}" unless File.exist?(path)

        File.read(path)
      end

      sig { params(filename: String).returns(String) }
      def file_path(filename)
        File.join(@step_dir, filename)
      end
    end
  end
end

# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Workflow
    class Definition
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(T::Hash[Symbol, StepDefinition]) }
      attr_reader :steps

      sig { returns(T::Array[Symbol]) }
      attr_reader :sorted_steps

      sig { params(name: String).void }
      def initialize(name)
        @name = T.let(name, String)
        @steps = T.let({}, T::Hash[Symbol, StepDefinition])
        @sorted_steps = T.let([], T::Array[Symbol])
      end

      sig { params(name: String, block: T.proc.params(builder: Definition).void).returns(Definition) }
      def self.define(name, &block)
        definition = new(name)
        block.call(definition)
        definition.validate!
        definition.freeze
        definition
      end

      sig do
        params(
          name: Symbol,
          agent_class: T.class_of(Agent::Base),
          after: T.any(Symbol, T::Array[Symbol]),
          retries: T.nilable(Integer)
        ).void
      end
      def step(name, agent_class, after: [], retries: nil)
        deps = after.is_a?(Symbol) ? [after] : after
        @steps[name] = StepDefinition.new(
          name: name,
          agent_class: agent_class,
          after: deps,
          retries: retries
        )
      end

      sig { void }
      def validate!
        validate_dependencies!
        detect_cycles!
        @sorted_steps = topological_sort
      end

      private

      sig { void }
      def validate_dependencies!
        @steps.each do |name, step_def|
          step_def.after.each do |dep|
            unless @steps.key?(dep)
              raise MissingDependencyError,
                "Step :#{name} depends on :#{dep}, which does not exist"
            end
          end
        end
      end

      sig { void }
      def detect_cycles!
        # DFS-based cycle detection
        white = @steps.keys.to_set # unvisited
        gray = Set.new # in current path
        _black = Set.new # fully processed

        visit = T.let(nil, T.nilable(T.proc.params(node: Symbol).void))
        visit = lambda do |node|
          white.delete(node)
          gray.add(node)

          step_def = @steps.fetch(node)
          step_def.after.each do |dep|
            if gray.include?(dep)
              raise CircularDependencyError,
                "Circular dependency detected involving :#{dep}"
            end
            if white.include?(dep)
              T.must(visit).call(dep)
            end
          end

          gray.delete(node)
          _black.add(node)
        end

        while (node = white.first)
          visit.call(node)
        end
      end

      sig { returns(T::Array[Symbol]) }
      def topological_sort
        # Kahn's algorithm
        in_degree = T.let({}, T::Hash[Symbol, Integer])
        @steps.each_key { |name| in_degree[name] = 0 }
        @steps.each_value do |step_def|
          step_def.after.each do |_dep|
            in_degree[step_def.name] = T.must(in_degree[step_def.name]) + 1
          end
        end

        queue = in_degree.select { |_, deg| deg == 0 }.keys
        sorted = T.let([], T::Array[Symbol])

        until queue.empty?
          node = T.must(queue.shift)
          sorted << node

          # Find steps that depend on this node
          @steps.each do |name, step_def|
            if step_def.after.include?(node)
              in_degree[name] = T.must(in_degree[name]) - 1
              queue << name if in_degree[name] == 0
            end
          end
        end

        sorted
      end
    end
  end
end

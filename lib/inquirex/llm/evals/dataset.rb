# frozen_string_literal: true

module Inquirex
  module LLM
    module Evals
      # What one dataset folder shares across its cases: the flow in dsl.rb,
      # whose single `extract` step supplies the prompt and the schema, and
      # schema.rb, that schema copied out verbatim so a change to either is
      # caught by `agent-evals verify` instead of silently moving the scores.
      #
      #   evals/datasets/05-managed-it-services/
      #     dsl.rb                       the flow, loaded with unsafe: true (a file we author)
      #     schema.rb                    the extract step's schema, as a Ruby Hash literal
      #     cases/<variant>/input.txt    what a visitor wrote
      #     cases/<variant>/expected.json the answers a perfect extraction returns
      class Dataset
        attr_reader :name, :path

        # @param name [String] the folder under datasets/, e.g. "05-managed-it-services"
        # @param root [String] the suite root, the directory holding datasets/
        def initialize(name, root:)
          @name = name
          @path = File.join(root, "datasets", name)
        end

        # @return [String]
        def dsl_path = File.join(path, "dsl.rb")

        # @return [String]
        def schema_path = File.join(path, "schema.rb")

        # @return [Inquirex::Definition]
        # @raise [Errno::ENOENT, Inquirex::Errors::Error] when dsl.rb is missing or will not load
        def definition
          @definition ||= Inquirex.load_dsl(File.read(dsl_path), unsafe: true)
        end

        # The flow's one `extract` step, the one the cases exercise.
        #
        # @return [Inquirex::LLM::Node]
        # @raise [Error] when the flow has no extract step with a schema, or more than one
        def node
          @node ||= begin
            nodes = definition.steps.values.select { |step| step.is_a?(Inquirex::LLM::Node) && step.schema }
            raise Error, "#{name}/dsl.rb: expected one extract step with a schema, found #{nodes.size}" unless nodes.one?

            nodes.first
          end
        end

        # The copied schema, read from schema.rb.
        #
        # @return [Inquirex::LLM::Schema]
        def schema
          # A Ruby Hash literal in a file we author; eval is how it is read, as load_dsl reads dsl.rb.
          @schema ||= Inquirex::LLM::Schema.new(**eval(File.read(schema_path), binding, schema_path)) # rubocop:disable Security/Eval
        end

        # The step the extract reads from, which a case's input.txt answers.
        #
        # @return [Symbol]
        def source_step = node.from_steps.first

        # Offline checks of the shared files, for `agent-evals verify`.
        #
        # @return [Array<String>] problems; empty when the dataset is sound
        def problems
          problems = []
          problems << "#{name}/schema.rb differs from the DSL's extract schema" unless schema == node.schema
          problems << "#{name}/dsl.rb: the extract step reads from no step" if node.from_steps.empty?
          problems
        rescue Errno::ENOENT, Inquirex::Errors::Error, Error, SyntaxError, ArgumentError => e
          ["#{name}: #{e.class}: #{e.message.lines.first&.strip}"]
        end
      end
    end
  end
end

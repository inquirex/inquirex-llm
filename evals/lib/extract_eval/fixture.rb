# frozen_string_literal: true

module ExtractEval
  # One eval case: a flow definition, its extract step's schema, a paragraph a
  # visitor might write, and the answers a perfect extraction would produce.
  # The files share a basename across dsls/, schema/, and a dataset's
  # extracted-answers/ and ground-truth/ (datasets/<name>/...); the two-digit
  # prefix is the difficulty, 01 easiest.
  class Fixture
    DEFAULT_DATASET = "clear"

    attr_reader :name, :root, :dataset

    # @param name [String] shared basename without extension, e.g. "03_home-remodeling"
    # @param dataset [String] a folder under datasets/, e.g. "clear" or "vague"
    # @param root [String] the evals/ directory
    def initialize(name, dataset: DEFAULT_DATASET, root: ROOT)
      @name = name
      @dataset = dataset
      @root = root
    end

    # @return [Integer] 1 (direct answers) through 10 (an essay)
    def difficulty = Integer(name[/\A\d+/], 10)

    def dsl_path = File.join(root, "dsls", "#{name}.rb")
    def schema_path = File.join(root, "schema", "#{name}.rb")
    def text_path = File.join(root, "datasets", dataset, "extracted-answers", "#{name}.txt")
    def truth_path = File.join(root, "datasets", dataset, "ground-truth", "#{name}.json")

    # The flow, loaded with `unsafe: true`: these are files we author.
    #
    # @return [Inquirex::Definition]
    def definition
      @definition ||= Inquirex.load_dsl(File.read(dsl_path), unsafe: true)
    end

    # The flow's single `extract` step.
    #
    # @return [Inquirex::LLM::Node]
    # @raise [Error] when the flow has no extract step, or more than one
    def node
      @node ||= begin
        nodes = definition.steps.values.select { |step| step.is_a?(Inquirex::LLM::Node) && step.schema }
        raise Error, "#{name}: expected one extract step with a schema, found #{nodes.size}" unless nodes.one?

        nodes.first
      end
    end

    # The copied schema, evaluated from schema/<name>.rb.
    #
    # @return [Inquirex::LLM::Schema]
    def schema
      @schema ||= Inquirex::LLM::Schema.new(**eval(File.read(schema_path), binding, schema_path)) # rubocop:disable Security/Eval
    end

    # @return [String] the free-form paragraph
    def text = @text ||= File.read(text_path).strip

    # @return [Hash{String => Object}] the expected extraction
    def truth = @truth ||= JSON.parse(File.read(truth_path))

    # The step the extract node reads from, which the visitor's text answers.
    #
    # @return [Symbol]
    def source_step = node.from_steps.first

    # Every flow's fixture in one dataset, by difficulty.
    #
    # @param root [String]
    # @param dataset [String]
    # @param only [Array<String>] prefixes or names to keep ("03", "09_tax"); empty keeps all
    # @return [Array<Fixture>]
    # @raise [Error] when the dataset does not exist
    def self.all(root: ROOT, dataset: DEFAULT_DATASET, only: [])
      unless datasets(root: root).include?(dataset)
        raise Error, "no dataset #{dataset.inspect}; have #{datasets(root: root).join(", ")}"
      end

      names = Dir[File.join(root, "dsls", "*.rb")].map { File.basename(it, ".rb") }.sort
      names = names.select { |name| only.any? { name.start_with?(it) } } unless only.empty?
      names.map { new(it, dataset: dataset, root: root) }
    end

    # @param root [String]
    # @return [Array<String>] the folders under datasets/
    def self.datasets(root: ROOT)
      Dir[File.join(root, "datasets", "*/")].map { File.basename(it) }.sort
    end
  end
end

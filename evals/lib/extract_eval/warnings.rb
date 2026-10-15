# frozen_string_literal: true

require "logger"

module ExtractEval
  # Everything a run would otherwise print as a warning while its progress
  # bars redraw: cases that failed, and what Braintrust, RubyLLM and Ruby
  # itself log. Printed among the bars, each one breaks the redraw; collected
  # here, they are saved to one file, and the run prints only how many.
  #
  # It quacks as an IO, so a Logger, and $stderr, can write to it. Threads
  # share it.
  class Warnings
    def initialize
      @lines = []
      @lock = Mutex.new
    end

    # @param text [#to_s]
    # @return [self]
    def record(text)
      text = text.to_s.chomp
      @lock.synchronize { @lines << text } unless text.strip.empty?
      self
    end

    # @return [Integer] the bytes "written", as IO#write does
    def write(*texts)
      texts.each { record(it) }
      texts.sum { it.to_s.bytesize }
    end

    def puts(*texts) = texts.each { record(it) } && nil
    def print(*texts) = write(*texts) && nil
    def <<(text) = record(text)
    def flush = self
    def sync = true
    def sync=(_value); end
    def close = nil
    def tty? = false

    # @return [Integer]
    def count = @lock.synchronize { @lines.size }

    # @return [Array<String>]
    def to_a = @lock.synchronize { @lines.dup }

    # @return [Boolean] whether nothing was recorded
    def none? = count.zero?

    # @param path [String]
    # @return [String] the path
    def save(path)
      File.write(path, "#{to_a.join("\n\n")}\n")
      path
    end

    # Runs the block with Braintrust's and RubyLLM's loggers, $stderr and
    # Ruby's own warnings writing here, and puts them back after.
    #
    # @return [Object] what the block returns
    def capture
      braintrust = Braintrust::Log.logger
      ruby_llm = RubyLLM.instance_variable_get(:@logger)
      stderr = $stderr
      logger = Logger.new(self, level: Logger::WARN)
      Braintrust::Log.logger = logger
      RubyLLM.instance_variable_set(:@logger, logger)
      $stderr = self
      yield
    ensure
      Braintrust::Log.logger = braintrust
      RubyLLM.instance_variable_set(:@logger, ruby_llm)
      $stderr = stderr
    end
  end
end

# frozen_string_literal: true

module Inquirex
  module LLM
    # Finds the numbers a text states, in digits or in words, so a model that
    # can only choose among options ({JevAdapter}) has the right one to
    # choose. "45", "1,200", "two", "forty-five" and "a hundred and forty"
    # all come back as integers.
    module Numbers
      UNITS = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen
                 fifteen sixteen seventeen eighteen nineteen].each_with_index.to_h.freeze
      TENS = { "twenty" => 20, "thirty" => 30, "forty" => 40, "fifty" => 50, "sixty" => 60,
               "seventy" => 70, "eighty" => 80, "ninety" => 90 }.freeze
      SCALES = { "hundred" => 100, "thousand" => 1000 }.freeze
      WORD = /\b(?:#{(UNITS.keys + TENS.keys + SCALES.keys + %w[dozen]).join("|")})\b/i
      DIGITS = /(?<![\d.])\d{1,3}(?:,\d{3})+(?![\d.])|(?<![\d.,])\d+(?![\d,]|\.\d)/

      module_function

      # @param text [String]
      # @return [Array<Integer>] distinct values, in order of first appearance
      def find(text)
        found = text.scan(DIGITS).map { Integer(it.delete(","), 10) }
        found.concat(word_numbers(text))
        found.uniq
      end

      # Runs of number words ("a hundred and forty", "forty-five"), each read
      # as one value.
      #
      # @return [Array<Integer>]
      def word_numbers(text)
        tokens = text.downcase.scan(/[a-z]+/)
        runs = tokens.chunk_while { |a, b| joins?(a, b) }
        runs.filter_map do |run|
          words = run.reject { it == "and" }
          next unless words.any? { WORD.match?(it) }

          words = words.drop_while { !WORD.match?(it) }
          value(words)
        end
      end

      def number_word?(word) = WORD.match?(word) || word == "a"

      # "and" continues a number only after a scale: "a hundred and forty" is
      # one value, "three dogs and two cats" is two.
      def joins?(left, right)
        return WORD.match?(right) if left == "and"
        return SCALES.key?(left) if right == "and"

        number_word?(left) && number_word?(right)
      end

      # @param words [Array<String>] e.g. %w[hundred forty] (from "a hundred and forty")
      # @return [Integer, nil]
      def value(words)
        total = 0
        current = 0
        words.each do |word|
          if UNITS.key?(word) then current += UNITS[word]
          elsif TENS.key?(word) then current += TENS[word]
          elsif word == "dozen" then current = [current, 1].max * 12
          elsif word == "hundred" then current = [current, 1].max * 100
          elsif word == "thousand"
            total += [current, 1].max * 1000
            current = 0
          end
        end
        total + current
      end
    end
  end
end

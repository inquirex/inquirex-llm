# frozen_string_literal: true

require "dotenv"
require "ruby_llm"

module ExtractEval
  # One-time process setup: secrets from the repo's .env, a check that every
  # key the run needs is there, RubyLLM pointed at OpenRouter, and Braintrust
  # tracing every RubyLLM call it makes.
  module Runtime
    module_function

    # The repo's .env, which holds every key the evals use.
    ENV_FILES = [File.expand_path("../.env", ROOT)].freeze

    # Loads the .env files that exist, without overriding what is already
    # set, so an exported variable beats the file.
    #
    # @return [void]
    def load_env
      files = ENV_FILES.select { File.exist?(it) }
      Dotenv.load(*files) unless files.empty?
    end

    # Fails before anything is called when a key the run needs is neither
    # exported nor in .env.
    #
    # @param names [Array<String>]
    # @return [void]
    # @raise [Error] naming every missing variable
    def require_env!(names)
      missing = names.uniq.select { ENV[it].to_s.strip.empty? }
      return if missing.empty?

      found = ENV_FILES.select { File.exist?(it) }
      where = found.empty? ? "there is no #{ENV_FILES.join(" or ")}" : "checked the environment, then #{found.join(", ")}"
      raise Error,
        "missing #{missing.join(", ")}: export them, or copy .env.example to .env and fill them in (#{where}); " \
        "an exported blank value wins over .env"
    end

    # @param braintrust [Boolean] false runs locally: no login, no experiment
    # @param keys [Array<String>] the variables the run's adapters need
    # @return [void]
    # @raise [Error] when a needed variable is missing
    def setup!(braintrust: true, keys: [])
      load_env
      require_env!(keys + (braintrust ? ["BRAINTRUST_API_KEY"] : []))
      Inquirex::LLM.reset_configuration! # the gem read ENV before .env was loaded
      RubyLLM.configure do |config|
        config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        config.openrouter_app_name = "inquirex-llm extract evals"
      end
      require "braintrust" # Eval.run scores locally too; only the login and tracing need the key
      return unless braintrust

      Braintrust.init(blocking_login: true, auto_instrument: false)
      Braintrust.instrument!(:ruby_llm)
    end

    # Opens a URL in the desktop browser.
    #
    # @param url [String]
    # @return [Boolean] whether the opener ran
    def browse(url)
      opener = RUBY_PLATFORM.include?("darwin") ? "open" : "xdg-open"
      system(opener, url, out: File::NULL, err: File::NULL) || false
    end
  end
end

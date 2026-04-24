# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tempfile"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

module TestSupport
  def with_env(overrides)
    previous_values = overrides.keys.to_h { |key| [key, ENV[key]] }

    overrides.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    previous_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def with_summary_file
    file = Tempfile.new("github-step-summary")
    yield(file)
  ensure
    file&.close
    file&.unlink
  end

  def reset_app_logger!
    AppLogger.instance_variable_set(:@logger, nil) if defined?(AppLogger)
  end
end

class Minitest::Test
  include TestSupport
end

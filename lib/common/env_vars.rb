# frozen_string_literal: true

require "uri"

module EnvVars
  def self.fetch(name)
    value = ENV[name]
    raise ArgumentError, "Missing required ENV: #{name}" if value.nil? || value.empty?

    value
  end

  def self.encode_password(value)
    URI.encode_www_form_component(value)
  rescue StandardError
    value
  end
end

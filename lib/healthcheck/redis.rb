# frozen_string_literal: true

require "redis"
require_relative "../common/env_vars"

module Healthcheck
  module Redis
    PASSWORD_PLACEHOLDER = "[YOUR-PASSWORD]"

    def self.call
      client = ::Redis.new(url: _redis_uri, connect_timeout: 5, read_timeout: 5, write_timeout: 5)
      pong = client.ping

      {
        success: pong == "PONG",
        message: "Pinged Redis successfully!"
      }
    ensure
      client&.close
    end

    def self._redis_uri
      url = EnvVars.fetch("REDIS_URL")
      password = EnvVars.fetch("REDIS_PASSWORD")

      url.sub(PASSWORD_PLACEHOLDER, EnvVars.encode_password(password))
    end
  end
end

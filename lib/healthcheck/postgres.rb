# frozen_string_literal: true

require "pg"
require_relative "../common/env_vars"

module Healthcheck
  module Postgres
    PASSWORD_PLACEHOLDER = "[YOUR-PASSWORD]"

    def self.call
      connection = ::PG.connect(_postgres_uri)
      connection.exec("SELECT 1")

      {
        success: true,
        message: "Pinged Postgres successfully!"
      }
    ensure
      connection&.close
    end

    def self._postgres_uri
      url = EnvVars.fetch("SUPABASE_DB_URL")
      password = EnvVars.fetch("SUPABASE_DB_PASSWORD")

      url.sub(PASSWORD_PLACEHOLDER, EnvVars.encode_password(password))
    end
  end
end

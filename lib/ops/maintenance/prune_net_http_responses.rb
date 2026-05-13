# frozen_string_literal: true

require "pg"
require_relative "../../common/env_vars"

module Maintenance
  module PruneNetHttpResponses
    PASSWORD_PLACEHOLDER = "[YOUR-PASSWORD]"
    QUERY = <<~SQL.freeze
      delete from net._http_response
    SQL

    def self.call
      connection = ::PG.connect(_postgres_uri)
      deleted_rows = connection.exec(QUERY).cmd_tuples

      {
        success: true,
        message: "Pruned #{deleted_rows} net._http_response rows"
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

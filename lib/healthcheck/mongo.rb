# frozen_string_literal: true

require "mongo"
require_relative "../common/env_vars"

module Healthcheck
  module Mongo
    PASSWORD_PLACEHOLDER = "<db_password>"
    APP_NAME = "supabase-keepalive-ping"

    def self.call
      client = ::Mongo::Client.new(
        _mongo_uri,
        app_name: APP_NAME,
        connect_timeout: 5,
        server_selection_timeout: 5,
        socket_timeout: 5
      )

      client.database.command(ping: 1).first

      {
        success: true,
        message: "Pinged MongoDB successfully!"
      }
    ensure
      client&.close
    end

    def self._mongo_uri
      url = EnvVars.fetch("ATLAS_DB_URL")
      password = EnvVars.fetch("ATLAS_DB_PASSWORD")

      url.sub(PASSWORD_PLACEHOLDER, EnvVars.encode_password(password))
    end
  end
end

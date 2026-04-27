# frozen_string_literal: true

require "pg"
require_relative "../../common/env_vars"

module Maintenance
  module PruneCronJobRuns
    PASSWORD_PLACEHOLDER = "[YOUR-PASSWORD]"
    RETENTION_INTERVAL = "7 days"
    QUERY = <<~SQL.freeze
      delete from cron.job_run_details
      where end_time < now() - interval '#{RETENTION_INTERVAL}';
    SQL

    def self.call
      connection = ::PG.connect(_postgres_uri)
      result = connection.exec(QUERY)
      deleted_rows = result.cmd_tuples

      {
        success: true,
        message: "Pruned #{deleted_rows} cron.job_run_details rows older than #{RETENTION_INTERVAL}"
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

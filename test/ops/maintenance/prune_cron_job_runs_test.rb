# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/ops/maintenance/prune_cron_job_runs"

class PruneCronJobRunsTest < Minitest::Test
  class FakeResult
    attr_reader :cmd_tuples

    def initialize(cmd_tuples)
      @cmd_tuples = cmd_tuples
    end
  end

  class FakeConnection
    attr_reader :queries, :closed, :uri

    def initialize(uri, deleted_rows:)
      @uri = uri
      @deleted_rows = deleted_rows
      @queries = []
      @closed = false
    end

    def exec(query)
      @queries << query
      FakeResult.new(@deleted_rows)
    end

    def close
      @closed = true
    end
  end

  def test_call_prunes_old_cron_job_run_records
    captured_connection = nil

    with_env(
      "SUPABASE_DB_URL" => "postgres://user:[YOUR-PASSWORD]@db.example.com:5432/postgres",
      "SUPABASE_DB_PASSWORD" => "pa$$ word"
    ) do
      PG.stub(:connect, lambda { |uri|
        captured_connection = FakeConnection.new(uri, deleted_rows: 12)
      }) do
        result = Maintenance::PruneCronJobRuns.call

        assert_equal true, result[:success]
        assert_equal "Pruned 12 cron.job_run_details rows older than 7 days", result[:message]
        assert_equal "postgres://user:pa%24%24+word@db.example.com:5432/postgres", captured_connection.uri
        assert_equal [Maintenance::PruneCronJobRuns::QUERY], captured_connection.queries
        assert_equal true, captured_connection.closed
      end
    end
  end
end

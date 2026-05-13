# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/ops/maintenance/prune_net_http_responses"

class PruneNetHttpResponsesTest < Minitest::Test
  class FakeResult
    attr_reader :cmd_tuples

    def initialize(cmd_tuples)
      @cmd_tuples = cmd_tuples
    end
  end

  class FakeConnection
    attr_reader :queries, :closed, :uri

    def initialize(uri, deleted_rows_by_query:)
      @uri = uri
      @deleted_rows_by_query = deleted_rows_by_query
      @queries = []
      @closed = false
    end

    def exec(query)
      @queries << query
      FakeResult.new(@deleted_rows_by_query.fetch(query))
    end

    def close
      @closed = true
    end
  end

  def test_call_prunes_net_http_response_rows
    captured_connection = nil

    with_env(
      "SUPABASE_DB_URL" => "postgres://user:[YOUR-PASSWORD]@db.example.com:5432/postgres",
      "SUPABASE_DB_PASSWORD" => "pa$$ word"
    ) do
      PG.stub(:connect, lambda { |uri|
        captured_connection = FakeConnection.new(
          uri,
          deleted_rows_by_query: {
            Maintenance::PruneNetHttpResponses::QUERY => 61
          }
        )
      }) do
        result = Maintenance::PruneNetHttpResponses.call

        assert_equal true, result[:success]
        assert_equal "Pruned 61 net._http_response rows", result[:message]
        assert_equal "postgres://user:pa%24%24+word@db.example.com:5432/postgres", captured_connection.uri
        assert_equal [Maintenance::PruneNetHttpResponses::QUERY], captured_connection.queries
        assert_equal true, captured_connection.closed
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/ops/healthcheck/postgres"

class PostgresHealthcheckTest < Minitest::Test
  class FakeConnection
    attr_reader :queries, :closed, :uri

    def initialize(uri)
      @uri = uri
      @queries = []
      @closed = false
    end

    def exec(query)
      @queries << query
    end

    def close
      @closed = true
    end
  end

  def test_call_connects_with_encoded_uri_and_executes_select_1
    captured_connection = nil

    with_env(
      "SUPABASE_DB_URL" => "postgres://user:[YOUR-PASSWORD]@db.example.com:5432/postgres",
      "SUPABASE_DB_PASSWORD" => "pa$$ word"
    ) do
      PG.stub(:connect, lambda { |uri|
        captured_connection = FakeConnection.new(uri)
      }) do
        result = Healthcheck::Postgres.call

        assert_equal true, result[:success]
        assert_equal "Pinged Postgres successfully!", result[:message]
        assert_equal "postgres://user:pa%24%24+word@db.example.com:5432/postgres", captured_connection.uri
        assert_equal ["SELECT 1"], captured_connection.queries
        assert_equal true, captured_connection.closed
      end
    end
  end
end

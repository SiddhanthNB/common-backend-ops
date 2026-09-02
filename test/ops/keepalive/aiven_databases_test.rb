# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/ops/keepalive/aiven_databases"

class AivenDatabasesKeepaliveTest < Minitest::Test
  class FakePostgresConnection
    attr_reader :queries, :closed

    def initialize
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

  class FakeMysqlClient
    attr_reader :queries, :closed

    def initialize
      @queries = []
      @closed = false
    end

    def query(query)
      @queries << query
    end

    def close
      @closed = true
    end
  end

  def test_call_runs_temporary_write_probes_against_both_databases
    postgres_connection = FakePostgresConnection.new
    mysql_client = FakeMysqlClient.new
    captures = {}

    pg_connector = Object.new
    pg_connector.define_singleton_method(:connect) do |url|
      captures[:pg_url] = url
      postgres_connection
    end

    mysql_client_class = Object.new
    mysql_client_class.define_singleton_method(:new) do |**options|
      captures[:mysql_options] = options
      mysql_client
    end

    result = Keepalive::AivenDatabases.call(
      pg_url: "postgres://pg.example.com/app",
      mysql_url: "mysql://avnadmin:pa%24%24+word@mysql.example.com:12345/defaultdb?ssl-mode=REQUIRED",
      pg_connector: pg_connector,
      mysql_client_class: mysql_client_class
    )

    assert_equal true, result[:success]
    assert_equal(
      "2/2 Aiven databases completed keepalive probes",
      result[:message]
    )

    assert_equal "postgres://pg.example.com/app", captures[:pg_url]
    assert_equal(
      [
        "CREATE TEMP TABLE aiven_keepalive_probe (pinged_at TIMESTAMPTZ NOT NULL)",
        "INSERT INTO aiven_keepalive_probe (pinged_at) VALUES (NOW())",
        "SELECT pg_sleep(2)",
        "DROP TABLE aiven_keepalive_probe"
      ],
      postgres_connection.queries
    )
    assert_equal true, postgres_connection.closed

    assert_equal(
      [
        "CREATE TEMPORARY TABLE aiven_keepalive_probe (id BIGINT AUTO_INCREMENT PRIMARY KEY, pinged_at DATETIME(6) NOT NULL)",
        "INSERT INTO aiven_keepalive_probe (pinged_at) VALUES (CURRENT_TIMESTAMP(6))",
        "SELECT SLEEP(2)",
        "DROP TEMPORARY TABLE aiven_keepalive_probe"
      ],
      mysql_client.queries
    )
    assert_equal true, mysql_client.closed

    assert_equal(
      {
        host: "mysql.example.com",
        port: 12_345,
        username: "avnadmin",
        password: "pa$$+word",
        database: "defaultdb",
        connect_timeout: 5,
        read_timeout: 5,
        write_timeout: 5,
        ssl_mode: :required
      },
      captures[:mysql_options]
    )

    assert_equal(
      [
        {
          name: "Aiven PostgreSQL",
          success: true,
          message: "Temporary write probe succeeded"
        },
        {
          name: "Aiven MySQL",
          success: true,
          message: "Temporary write probe succeeded"
        }
      ],
      result[:results]
    )
  end

  def test_call_reports_partial_failure_and_continues
    pg_connector = Object.new
    pg_connector.define_singleton_method(:connect) do |_url|
      raise "postgres timeout"
    end

    mysql_client = FakeMysqlClient.new
    mysql_client_class = Object.new
    mysql_client_class.define_singleton_method(:new) do |**_options|
      mysql_client
    end

    result = Keepalive::AivenDatabases.call(
      pg_url: "postgres://pg.example.com/app",
      mysql_url: "mysql://avnadmin:secret@mysql.example.com/defaultdb",
      pg_connector: pg_connector,
      mysql_client_class: mysql_client_class
    )

    assert_equal false, result[:success]
    assert_equal(
      "1/2 Aiven databases completed keepalive probes",
      result[:message]
    )

    assert_equal(
      [
        {
          name: "Aiven PostgreSQL",
          success: false,
          message: "postgres timeout"
        },
        {
          name: "Aiven MySQL",
          success: true,
          message: "Temporary write probe succeeded"
        }
      ],
      result[:results]
    )

    assert_equal(
      Keepalive::AivenDatabases::MYSQL_KEEPALIVE_QUERIES,
      mysql_client.queries
    )
    assert_equal true, mysql_client.closed
  end
end

# frozen_string_literal: true

require "cgi"
require "mysql2"
require "pg"
require "uri"

require_relative "../../common/env_vars"

module Keepalive
  module AivenDatabases
    CONNECT_TIMEOUT_SECONDS = 5
    PROBE_DELAY_SECONDS = 2

    POSTGRES_KEEPALIVE_QUERIES = [
      "CREATE TEMP TABLE aiven_keepalive_probe (pinged_at TIMESTAMPTZ NOT NULL)",
      "INSERT INTO aiven_keepalive_probe (pinged_at) VALUES (NOW())",
      "SELECT pg_sleep(#{PROBE_DELAY_SECONDS})",
      "DROP TABLE aiven_keepalive_probe"
    ].freeze

    MYSQL_KEEPALIVE_QUERIES = [
      "CREATE TEMPORARY TABLE aiven_keepalive_probe (id BIGINT AUTO_INCREMENT PRIMARY KEY, pinged_at DATETIME(6) NOT NULL)",
      "INSERT INTO aiven_keepalive_probe (pinged_at) VALUES (CURRENT_TIMESTAMP(6))",
      "SELECT SLEEP(#{PROBE_DELAY_SECONDS})",
      "DROP TEMPORARY TABLE aiven_keepalive_probe"
    ].freeze

    def self.call(
      pg_url: EnvVars.fetch("AIVEN_PG_URL"),
      mysql_url: EnvVars.fetch("AIVEN_MYSQL_URL"),
      pg_connector: PG,
      mysql_client_class: Mysql2::Client
    )
      results = [
        _postgres_result(pg_url, pg_connector),
        _mysql_result(mysql_url, mysql_client_class)
      ]

      passed = results.count { |result| result[:success] }

      {
        success: passed == results.size,
        message: "#{passed}/#{results.size} Aiven databases completed keepalive probes",
        results: results
      }
    end

    def self._postgres_result(pg_url, pg_connector)
      connection = pg_connector.connect(pg_url)

      POSTGRES_KEEPALIVE_QUERIES.each do |query|
        connection.exec(query)
      end

      {
        name: "Aiven PostgreSQL",
        success: true,
        message: "Temporary write probe succeeded"
      }
    rescue StandardError => error
      {
        name: "Aiven PostgreSQL",
        success: false,
        message: error.message
      }
    ensure
      connection&.close
    end

    def self._mysql_result(mysql_url, mysql_client_class)
      client = mysql_client_class.new(**_mysql_options(mysql_url))

      MYSQL_KEEPALIVE_QUERIES.each do |query|
        client.query(query)
      end

      {
        name: "Aiven MySQL",
        success: true,
        message: "Temporary write probe succeeded"
      }
    rescue StandardError => error
      {
        name: "Aiven MySQL",
        success: false,
        message: error.message
      }
    ensure
      client&.close
    end

    def self._mysql_options(mysql_url)
      uri = URI.parse(mysql_url)
      query_params = URI.decode_www_form(uri.query.to_s).to_h

      options = {
        host: uri.host,
        port: uri.port,
        username: _decode_uri_component(uri.user),
        password: _decode_uri_component(uri.password),
        database: uri.path.sub(%r{\A/}, ""),
        connect_timeout: CONNECT_TIMEOUT_SECONDS,
        read_timeout: CONNECT_TIMEOUT_SECONDS,
        write_timeout: CONNECT_TIMEOUT_SECONDS,
        ssl_mode: _mysql_ssl_mode(
          query_params["ssl-mode"] || query_params["ssl_mode"]
        )
      }

      options.reject { |_key, value| value.nil? || value == "" }
    end

    def self._mysql_ssl_mode(raw_value)
      value = raw_value.to_s.strip.downcase
      return :required if value.empty?

      case value
      when "disabled"
        :disabled
      when "preferred"
        :preferred
      when "required"
        :required
      when "verify_ca"
        :verify_ca
      when "verify_identity"
        :verify_identity
      else
        :required
      end
    end

    def self._decode_uri_component(value)
      return nil if value.nil?

      URI::RFC2396_PARSER.unescape(value)
    end
  end
end

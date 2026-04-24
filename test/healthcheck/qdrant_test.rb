# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/healthcheck/qdrant"

class QdrantHealthcheckTest < Minitest::Test
  Response = Struct.new(:status) do
    def json
      {}
    end
  end

  def test_call_checks_healthz_and_collections
    captures = { urls: [] }

    client = Object.new
    client.define_singleton_method(:get) do |url|
      captures[:urls] << url

      case url
      when "https://qdrant.example.com/healthz"
        Response.new(200)
      when "https://qdrant.example.com/collections"
        Response.new(200)
      else
        raise "unexpected url: #{url}"
      end
    end

    with_env(
      "QDRANT_URL" => "https://qdrant.example.com/",
      "QDRANT_ACCESS_KEY" => "secret"
    ) do
      HTTPX.stub(:with, lambda { |options|
        captures[:options] = options
        client
      }) do
        result = Healthcheck::Qdrant.call

        assert_equal true, result[:success]
        assert_equal "Qdrant healthz=200, collections=200", result[:message]
        assert_equal(
          {
            timeout: {
              connect_timeout: 5,
              write_timeout: 5,
              operation_timeout: 10
            },
            headers: {
              "api-key" => "secret"
            }
          },
          captures[:options]
        )
        assert_equal(
          [
            "https://qdrant.example.com/healthz",
            "https://qdrant.example.com/collections"
          ],
          captures[:urls]
        )
      end
    end
  end

  def test_call_reports_failed_healthz_without_collections_request
    captures = { urls: [] }

    client = Object.new
    client.define_singleton_method(:get) do |url|
      captures[:urls] << url
      Response.new(503)
    end

    with_env(
      "QDRANT_URL" => "https://qdrant.example.com/",
      "QDRANT_ACCESS_KEY" => "secret"
    ) do
      HTTPX.stub(:with, ->(*) { client }) do
        result = Healthcheck::Qdrant.call

        assert_equal false, result[:success]
        assert_equal "Qdrant healthz=503", result[:message]
        assert_equal ["https://qdrant.example.com/healthz"], captures[:urls]
      end
    end
  end
end

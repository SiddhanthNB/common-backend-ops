# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/ops/healthcheck/mongo"

class MongoHealthcheckTest < Minitest::Test
  class FakeDatabase
    attr_reader :commands

    def initialize
      @commands = []
    end

    def command(command)
      @commands << command
      [{ "ok" => 1 }]
    end
  end

  class FakeClient
    attr_reader :database, :closed, :uri

    def initialize(uri)
      @uri = uri
      @database = FakeDatabase.new
      @closed = false
    end

    def close
      @closed = true
    end
  end

  def test_call_connects_with_encoded_uri_and_pings_mongo
    captured_client = nil

    with_env(
      "MONGO_CLUSTER_URI" => "mongodb+srv://user:<db_password>@cluster0.example.mongodb.net/?retryWrites=true&w=majority",
      "MONGO_USER_PASSWORD" => "pa$$ word"
    ) do
      Mongo::Client.stub(:new, lambda { |uri, **_options|
        captured_client = FakeClient.new(uri)
      }) do
        result = Healthcheck::Mongo.call

        assert_equal true, result[:success]
        assert_equal "Pinged MongoDB successfully!", result[:message]
        assert_equal "mongodb+srv://user:pa%24%24+word@cluster0.example.mongodb.net/?retryWrites=true&w=majority", captured_client.uri
        assert_equal [{ ping: 1 }], captured_client.database.commands
        assert_equal true, captured_client.closed
      end
    end
  end
end

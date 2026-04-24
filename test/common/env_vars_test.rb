# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/common/env_vars"

class EnvVarsTest < Minitest::Test
  def test_fetch_returns_present_value
    with_env("EXAMPLE_ENV_VAR" => "value") do
      assert_equal "value", EnvVars.fetch("EXAMPLE_ENV_VAR")
    end
  end

  def test_fetch_raises_for_missing_value
    with_env("EXAMPLE_ENV_VAR" => nil) do
      error = assert_raises(ArgumentError) { EnvVars.fetch("EXAMPLE_ENV_VAR") }

      assert_equal "Missing required ENV: EXAMPLE_ENV_VAR", error.message
    end
  end

  def test_encode_password_url_encodes_reserved_characters
    assert_equal "pa%24%24+word%2Fwith%3Fchars", EnvVars.encode_password("pa$$ word/with?chars")
  end
end

# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/common/app_logger"
require_relative "../../lib/common/service_task_runner"

class ServiceTaskRunnerTest < Minitest::Test
  def setup
    reset_app_logger!
  end

  def test_run_writes_success_summary
    with_summary_file do |file|
      with_env("GITHUB_STEP_SUMMARY" => file.path) do
        stdout, = capture_io do
          ServiceTaskRunner.run("Sample Task") do
            { success: true, message: "all good" }
          end
        end

        summary = File.read(file.path)

        assert_includes stdout, "Starting Sample Task"
        assert_includes stdout, "Sample Task: all good"
        assert_includes summary, "## Sample Task"
        assert_includes summary, "- Status: PASS"
        assert_includes summary, "- Details: all good"
      end
    end
  end

  def test_run_exits_with_failure_for_expected_failed_result
    with_summary_file do |file|
      with_env("GITHUB_STEP_SUMMARY" => file.path) do
        error = assert_raises(SystemExit) do
          capture_io do
            ServiceTaskRunner.run("Sample Task") do
              { success: false, message: "something failed" }
            end
          end
        end

        summary = File.read(file.path)

        assert_equal 1, error.status
        assert_includes summary, "- Status: FAIL"
        assert_includes summary, "- Details: something failed"
      end
    end
  end
end

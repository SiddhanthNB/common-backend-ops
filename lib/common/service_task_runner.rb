# frozen_string_literal: true

require_relative "app_logger"
require_relative "github_step_summary"

module ServiceTaskRunner
  def self.run(title)
    AppLogger.info("Starting #{title}")
    result = yield

    _log_result(title, result)
    GithubStepSummary.append(
      _summary(
        title,
        status: result.fetch(:success) ? "PASS" : "FAIL",
        message: result.fetch(:message)
      )
    )

    exit(1) unless result.fetch(:success)
  rescue StandardError => error
    AppLogger.error("#{title} failed: #{error.message}")
    GithubStepSummary.append(_summary(title, status: "FAIL", error: error.message))
    exit(1)
  end

  def self._log_result(title, result)
    message = "#{title}: #{result.fetch(:message)}"

    if result.fetch(:success)
      AppLogger.info(message)
    else
      AppLogger.error(message)
    end
  end

  def self._summary(title, status:, message: nil, error: nil)
    lines = [
      "## #{title}",
      "",
      "- Status: #{status}"
    ]
    details = error || message
    lines << "- Details: #{details}" if details
    lines.join("\n")
  end
end

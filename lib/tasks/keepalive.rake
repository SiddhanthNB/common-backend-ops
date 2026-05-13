require "yaml"

namespace :keepalive do
  desc "Ping the Core Nest keepalive endpoint"
  task :core_nest do
    require_relative "../common/service_task_runner"
    require_relative "../ops/keepalive/core_nest"

    config_path = File.expand_path("../../config/keepalive/core_nest.yaml", __dir__)
    config = YAML.safe_load(File.read(config_path), aliases: false) || {}
    url = config.fetch("url")
    timeout_milliseconds = Integer(config.fetch("timeout_milliseconds", 90_000))

    ServiceTaskRunner.run("Core Nest Keepalive") do
      Keepalive::CoreNest.call(url: url, timeout_milliseconds: timeout_milliseconds)
    end
  end

  desc "Wake Streamlit apps listed in config/keepalive/streamlit.yaml"
  task :streamlit do
    require_relative "../common/app_logger"
    require_relative "../common/github_step_summary"
    require_relative "../ops/keepalive/streamlit"

    config_path = File.expand_path("../../config/keepalive/streamlit.yaml", __dir__)
    config = YAML.safe_load(File.read(config_path), aliases: false) || {}
    targets = config.fetch("targets", [])
    concurrency = Integer(config.fetch("concurrency", 2))

    raise "No Streamlit targets configured in #{config_path}" if targets.empty?
    raise "Invalid Streamlit concurrency: #{concurrency}" if concurrency <= 0

    orchestrator = Keepalive::Streamlit::Orchestrator.new(urls: targets, concurrency: concurrency)
    title = "Streamlit Keepalive"

    AppLogger.info("Starting #{title}")
    result = orchestrator.call

    success = result[:failed].zero?
    message = "#{result[:passed]}/#{result[:total]} Streamlit targets passed"

    if success
      AppLogger.info("#{title}: #{message}")
    else
      AppLogger.error("#{title}: #{message}")
    end

    GithubStepSummary.append(
      [
        "## #{title}",
        "",
        "- Status: #{success ? 'PASS' : 'FAIL'}",
        "- Details: #{message}"
      ].join("\n")
    )

    result[:results].each do |target_result|
      GithubStepSummary.append(
        [
          "### #{target_result[:url]}",
          "",
          "- Status: #{target_result[:success] ? 'SUCCESS' : 'FAILURE'}",
          "- Details: #{target_result[:message]}"
        ].join("\n")
      )
    end

    exit(1) unless success
  rescue StandardError => error
    AppLogger.error("#{title} failed: #{error.message}")
    GithubStepSummary.append(
      [
        "## #{title}",
        "",
        "- Status: FAIL",
        "- Details: #{error.message}"
      ].join("\n")
    )
    exit(1)
  end

  desc "Run SELECT 1 against the Aiven PostgreSQL and MySQL instances"
  task :aiven_databases do
    require_relative "../common/app_logger"
    require_relative "../common/github_step_summary"
    require_relative "../ops/keepalive/aiven_databases"

    title = "Aiven Databases Keepalive"

    AppLogger.info("Starting #{title}")
    result = Keepalive::AivenDatabases.call

    success = result.fetch(:success)
    message = result.fetch(:message)

    if success
      AppLogger.info("#{title}: #{message}")
    else
      AppLogger.error("#{title}: #{message}")
    end

    GithubStepSummary.append(
      [
        "## #{title}",
        "",
        "- Status: #{success ? 'PASS' : 'FAIL'}",
        "- Details: #{message}"
      ].join("\n")
    )

    result.fetch(:results).each do |target_result|
      GithubStepSummary.append(
        [
          "### #{target_result[:name]}",
          "",
          "- Status: #{target_result[:success] ? 'SUCCESS' : 'FAILURE'}",
          "- Details: #{target_result[:message]}"
        ].join("\n")
      )
    end

    exit(1) unless success
  rescue StandardError => error
    AppLogger.error("#{title} failed: #{error.message}")
    GithubStepSummary.append(
      [
        "## #{title}",
        "",
        "- Status: FAIL",
        "- Details: #{error.message}"
      ].join("\n")
    )
    exit(1)
  end
end

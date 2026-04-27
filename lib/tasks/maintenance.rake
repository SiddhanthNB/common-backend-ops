require_relative "../common/service_task_runner"

namespace :maintenance do
  desc "Prune old cron job run records"
  task :prune_cron_job_runs do
    require_relative "../ops/maintenance/prune_cron_job_runs"

    ServiceTaskRunner.run("Prune Cron Job Runs") do
      Maintenance::PruneCronJobRuns.call
    end
  end
end

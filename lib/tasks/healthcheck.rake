require_relative "../common/service_task_runner"

namespace :healthcheck do
  desc "Probe Redis"
  task :redis do
    require_relative "../ops/healthcheck/redis"

    ServiceTaskRunner.run("Redis Healthcheck") do
      Healthcheck::Redis.call
    end
  end

  desc "Probe MongoDB Atlas"
  task :mongo do
    require_relative "../ops/healthcheck/mongo"

    ServiceTaskRunner.run("MongoDB Healthcheck") do
      Healthcheck::Mongo.call
    end
  end

  desc "Probe Qdrant"
  task :qdrant do
    require_relative "../ops/healthcheck/qdrant"

    ServiceTaskRunner.run("Qdrant Healthcheck") do
      Healthcheck::Qdrant.call
    end
  end

  desc "Probe Supabase Postgres"
  task :postgres do
    require_relative "../ops/healthcheck/postgres"

    ServiceTaskRunner.run("Postgres Healthcheck") do
      Healthcheck::Postgres.call
    end
  end
end

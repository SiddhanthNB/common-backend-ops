# common-backend-ops

This repository is the operational automation companion to the Supabase project `common-backend`.

The Supabase project remains the actual backend runtime and infrastructure layer. This repository exists to hold shared scheduled jobs, probes, and keepalive tasks that support that backend and other shared hobby-infra services.

One of the supported projects is [core-nest](https://github.com/SiddhanthNB/core-nest).

## Purpose

This repo is used for things like:

- keepalive jobs for shared services
- healthchecks for infrastructure dependencies
- lightweight operational automation
- GitHub Actions scheduled tasks backed by Ruby code

## Implementation Direction

The current approach is:

- Ruby for implementation
- `rake` as the task interface
- GitHub Actions as the scheduler/orchestrator
- task logic under `lib/`
- thin task entrypoints under `rakelib/`

## Current Responsibilities

At the moment, this repo contains automation for:

- Streamlit keepalive jobs
- Core Nest keepalive pings
- healthchecks for Redis, MongoDB, Qdrant, and Supabase Postgres

## Note

This repository is intentionally not the application backend itself. Supabase `common-backend` remains the runtime backend and infrastructure layer, while this repo handles shared ops and automation concerns around it.

## Running Tasks

List available tasks:

```bash
bundle exec rake -T
```

Run a task manually:

```bash
bundle exec rake keepalive:core_nest
bundle exec rake keepalive:streamlit
bundle exec rake healthcheck:redis
```

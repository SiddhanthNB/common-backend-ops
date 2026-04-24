# common-backend-ops

This repository contains shared operational automation for the Supabase project `common-backend`.

It is the ops companion to the backend, not the backend itself.

Current tasks include:

- Streamlit keepalives
- Core Nest keepalive pings for [core-nest](https://github.com/SiddhanthNB/core-nest)
- healthchecks for Redis, MongoDB, Qdrant, and Supabase Postgres

List available tasks:

```bash
bundle exec rake -T
```

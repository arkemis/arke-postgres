# Setup

- Add the deps:

  ```elixir
  {:arke, "~> 0.6.0"},
  {:arke_postgres, "~> 0.5.0"}
  ```

- Wire the persistence map in **compile-time config** (`config/config.exs`).
  Arke core captures it in a module attribute, so `config/runtime.exs` or
  `Application.put_env/3` silently yields `nil` function references and a
  crash on first use. If you change it, recompile the dep
  (`mix deps.compile arke --force`):

  ```elixir
  config :arke,
    persistence: %{
      arke_postgres: %{
        transaction: &ArkePostgres.transaction/2,
        create: &ArkePostgres.create/2,
        update: &ArkePostgres.update/2,
        update_key: &ArkePostgres.update_key/2,
        delete: &ArkePostgres.delete/2,
        execute_query: &ArkePostgres.Query.execute/2,
        create_project: &ArkePostgres.create_project/1,
        delete_project: &ArkePostgres.delete_project/1,
        repo: ArkePostgres.Repo,
        init: &ArkePostgres.init/0
      }
    }
  ```

- Do NOT omit `update_key:`, `repo:` or `init:` even though older examples do:
  `update_key` is required by `Arke.QueryManager.update_key/2` (arke ≥ 0.6.0),
  `repo` by `mix arke.seed_project`, and `init` by `mix arke.export_data`.
- Do NOT omit `transaction:` (arke ≥ 0.9.0): without it the write pipeline
  runs on an identity seam — no rollback, no `after_commit` deferral.
  `ArkePostgres.transaction/2` rolls back on `{:error, _}` and translates
  raised constraint violations to
  `{:error, %{constraint: name, message: msg}}` after the rollback.
- Configure the repo and register it for `mix ecto.*`:

  ```elixir
  config :arke_postgres, ArkePostgres.Repo,
    username: System.get_env("DB_USER"),
    password: System.get_env("DB_PASSWORD"),
    hostname: System.get_env("DB_HOSTNAME"),
    database: System.get_env("DB_NAME"),
    pool_size: 10

  config :arke_postgres, ecto_repos: [ArkePostgres.Repo]
  ```

- The env vars `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` are checked
  at application boot; if any is missing the app calls `System.halt(0)` — note
  the **exit code 0**, so supervisors and orchestrators see a clean exit.
  Export them before any `mix run`, release start or CI job.
- The package ships empty `config/*.exs` files — all configuration is the
  consuming app's responsibility.
- Bootstrap from scratch:

  ```bash
  mix ecto.create
  mix arke_postgres.create_project --id arke_system
  mix arke.seed_project --project arke_system
  ```

- For tests, use the SQL sandbox:
  `config :arke_postgres, ArkePostgres.Repo, pool: Ecto.Adapters.SQL.Sandbox`.

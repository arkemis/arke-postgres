# ArkePostgres — LLM Knowledge Pack

ArkePostgres is the **PostgreSQL persistence adapter** for the Arke ecosystem — an Elixir package that translates Arke's dynamic domain model into PostgreSQL storage. It provides the database layer that Arke's core depends on: CRUD operations, query execution, project (schema) management, and boot-time initialization of ETS managers from persisted data.

This package is the bridge between Arke's in-memory schema world and a relational database. It plugs into Arke through the persistence-function seam documented in the [arke knowledge pack](https://github.com/arkemis/arke/llms/index.md).

**Current version:** 0.5.0 · **License:** Apache-2.0 · **Source:** <https://github.com/arkemis/arke-postgres> · **Hex:** <https://hex.pm/packages/arke_postgres>

## Read order

Start with `overview.md`. After that the files are independent — jump to whichever matches the task.

| File | When to read |
|---|---|
| [overview.md](overview.md) | **Always read first.** Mental model: dual persistence modes, multi-tenant schemas, query translation, initialization flow. |
| [reference.md](reference.md) | Looking up a specific module or function signature. |
| [recipes.md](recipes.md) | Common tasks: configuring the adapter, creating projects, running queries, writing migrations. |
| [gotchas.md](gotchas.md) | Something behaves unexpectedly. Sharp edges and non-obvious defaults. |
| [design.md](design.md) | Questions about *why* something is shaped this way — useful when debugging or evaluating changes. |

## What ArkePostgres is

- The persistence backend that Arke requires to function. Without it (or an equivalent), all CRUD through `Arke.QueryManager` crashes.
- The boot-time data loader that populates Arke's ETS managers from PostgreSQL.
- The SQL query translator that converts Arke's `%Query{}` DSL into Ecto queries with JSONB-aware fragments.
- The multi-tenant schema manager that provisions and tears down PostgreSQL schemas per project.

## What ArkePostgres is not

- Not a standalone ORM. It doesn't expose Ecto schemas for general use — they're internal implementation details.
- Not the query builder. The query DSL lives in `arke` core (`Arke.Core.Query`, `Arke.QueryManager`). ArkePostgres *executes* those queries.
- Not the validation layer. Validation happens in `arke` core before persistence functions are called.

## Minimum you need to use it

```elixir
# mix.exs
{:arke, "~> 0.6.0"},
{:arke_postgres, "~> 0.5.0"}

# config/config.exs
config :arke,
  persistence: %{
    arke_postgres: %{
      create: &ArkePostgres.create/2,
      update: &ArkePostgres.update/2,
      delete: &ArkePostgres.delete/2,
      execute_query: &ArkePostgres.Query.execute/2,
      create_project: &ArkePostgres.create_project/1,
      delete_project: &ArkePostgres.delete_project/1
    }
  }

# config/dev.exs (or runtime.exs)
config :arke_postgres, ArkePostgres.Repo,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  hostname: System.get_env("DB_HOSTNAME"),
  database: System.get_env("DB_NAME"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

Environment variables `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` must be set — the application halts at startup if any are missing. See [gotchas.md](gotchas.md#env-vars-are-checked-at-boot-and-halt-the-system).

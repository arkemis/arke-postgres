# Recipes — Common Tasks

Task-oriented snippets. Each recipe is self-contained; read [overview.md](overview.md) first for the mental model.

All recipes assume:
- `:arke_postgres` application started (which starts `:arke` as a dependency).
- Environment variables `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` set.
- `config :arke, persistence: %{arke_postgres: %{...}}` configured (see [index.md](index.md#minimum-you-need-to-use-it)).

---

## Configure ArkePostgres as persistence backend

```elixir
# mix.exs
defp deps do
  [
    {:arke, "~> 0.6.0"},
    {:arke_postgres, "~> 0.5.0"}
  ]
end

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

# config/dev.exs
config :arke_postgres, ArkePostgres.Repo,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  hostname: System.get_env("DB_HOSTNAME"),
  database: System.get_env("DB_NAME"),
  pool_size: 10
```

The persistence map key must be `:arke_postgres` regardless of the backend — this is hardcoded in Arke core. See [arke design.md](../../arke/llms/design.md#why-persistence-is-function-injected) for why.

---

## Create a new project

### Via Mix task (recommended for initial setup)

```bash
export DB_NAME=my_db DB_HOSTNAME=localhost DB_USER=postgres DB_PASSWORD=secret

mix arke_postgres.create_project --id my_project --label "My Project" --description "Tenant workspace"
```

This creates the PostgreSQL schema, runs migrations inside it, and inserts an `arke_project` unit in `arke_system`.

### At runtime (programmatic)

```elixir
alias Arke.{QueryManager, Boundary.ArkeManager}

project_arke = ArkeManager.get(:arke_project, :arke_system)
{:ok, _unit} = QueryManager.create(:arke_system, project_arke,
  id: "client_acme",
  label: "ACME Corp"
)
# Arke core's on_create hook calls ArkePostgres.create_project/1
# → CREATE SCHEMA "client_acme"
# → Run migrations with prefix: "client_acme"
```

Then seed the project:
```bash
mix arke.seed_project --project client_acme
```

---

## Delete a project

```elixir
project_unit = QueryManager.get_by(id: "client_acme", project: :arke_system)
{:ok, _} = QueryManager.delete(:arke_system, project_unit)
# Arke core's on_delete hook calls ArkePostgres.delete_project/1
# → DROP SCHEMA "client_acme" CASCADE
```

This is destructive and irreversible — all data in the schema is lost.

---

## Create a super_admin member for a project

```bash
mix arke_postgres.create_member --project my_project --username admin --password secret123
```

If the user doesn't exist, it's created in `:arke_system`. Then a `super_admin` member is created in the target project. Requires `arke_auth` in your dependencies.

Default credentials (if no `--username`/`--password` provided): `admin` / `admin`.

---

## Run migrations for a specific project

ArkePostgres runs migrations per-schema. When you create a project via the mix task, migrations run automatically. For manual migration:

```elixir
# Run all pending migrations for a specific project schema
Ecto.Migrator.run(ArkePostgres.Repo, :up, all: true, prefix: "my_project")
```

---

## Write a custom migration

```elixir
# priv/repo/migrations/20260422000000_add_custom_table.exs
defmodule ArkePostgres.Repo.Migrations.AddCustomTable do
  use Ecto.Migration

  def change do
    # This migration runs for every schema (every project)
    create table(:my_custom_table, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string
      add :data, :map, default: %{}
      timestamps()
    end
  end
end
```

Migrations are run with a `prefix:` option targeting each project schema. This means the table is created inside the project's PostgreSQL schema, not the public schema.

---

## Query with JSONB filters (understanding the SQL)

When you write an Arke query:

```elixir
import Arke.QueryManager

query(project: :my_project, arke: :person)
|> where(name__icontains: "ada", age__gte: 18)
|> all()
```

ArkePostgres translates this to SQL roughly equivalent to:

```sql
SELECT id, arke_id, data, metadata, inserted_at, updated_at
FROM my_project.arke_unit
WHERE (data -> 'name' ->> 'value')::text ILIKE '%ada%'
  AND (data -> 'age' ->> 'value')::integer >= 18
```

Each parameter type gets a specific SQL cast. See [reference.md](reference.md#column-mapping) for the full type→cast mapping.

---

## Query linked units (topology)

```elixir
import Arke.QueryManager

ada = QueryManager.get_by(id: "ada", project: :my_project)

# Find all children of ada via "friendship" links, up to depth 3
query(project: :my_project, arke: :person)
|> link(ada, direction: :child, depth: 3, type: "friendship")
|> all()
```

Behind the scenes, ArkePostgres builds a recursive CTE that walks the `arke_link` table starting from `ada.id`, following `parent_id → child_id` edges of type `"friendship"` up to 3 levels deep. The CTE result is joined with `arke_unit` to return full Unit records.

---

## Direct Ecto access (escape hatch)

For operations not supported by the Arke query DSL, you can use `ArkePostgres.Repo` directly:

```elixir
import Ecto.Query

# Raw SQL query against a specific project schema
ArkePostgres.Repo.all(
  from(u in "arke_unit",
    where: u.arke_id == "person",
    select: %{id: u.id, name: fragment("data -> 'name' ->> 'value'")}
  ),
  prefix: "my_project"
)

# Raw SQL
Ecto.Adapters.SQL.query(ArkePostgres.Repo, "SELECT count(*) FROM my_project.arke_unit", [])
```

Remember: JSONB values are wrapped as `{"value": X, "datetime": T}`. Access the actual value via `data -> 'field_name' ->> 'value'`, not `data ->> 'field_name'`.

---

## Get the generated SQL for a query

```elixir
import Arke.QueryManager

{sql, params} =
  query(project: :my_project, arke: :person)
  |> where(name__eq: "ada")
  |> raw()

IO.puts(sql)
# SELECT ... FROM "arke_unit" AS a0 WHERE ...
```

Useful for debugging query performance or understanding what ArkePostgres generates.

---

## Inspect the Ecto query struct

```elixir
ecto_query =
  query(project: :my_project, arke: :person)
  |> where(age__gte: 18)
  |> pseudo_query()

IO.inspect(ecto_query)
# %Ecto.Query{...}
```

Returns the Ecto query before execution — useful for debugging or composition.

---

## Understand the boot sequence

When your application starts:

```
Application.start(:arke_postgres)
  → Supervisor starts ArkePostgres.Repo (Ecto connection pool)
  → ArkePostgres.init()
    → check_env() — verify DB_NAME, DB_HOSTNAME, DB_USER, DB_PASSWORD
    → Query.get_project_record() — SELECT * FROM arke_system.arke_unit WHERE arke_id = 'arke_project'
    → Sort projects (arke_system first)
    → For each project:
      → Query.get_manager_units(project_id)
        → Load arke_link records (type = "parameter" or "group")
        → Load arke_unit records (arke_id in known arke/parameter IDs)
        → Parse into {parameters, arke_list, groups}
      → Arke.handle_manager(parameters, project_id, :parameter)
      → Arke.handle_manager(arke_list, project_id, :arke)
      → Arke.handle_manager(groups, project_id, :group)
    → :ok
```

If any step fails, the system halts. This is by design — see [design.md](design.md#why-init-halts-the-system-on-failure).

---

## Check if DB connection is healthy

```elixir
case ArkePostgres.check_env() do
  {:ok, nil} -> IO.puts("Env vars present")
  {:error, keys} -> IO.puts("Missing: #{inspect(keys)}")
end

# Test actual connectivity
case Ecto.Adapters.SQL.query(ArkePostgres.Repo, "SELECT 1", []) do
  {:ok, _} -> IO.puts("DB reachable")
  {:error, err} -> IO.puts("DB error: #{inspect(err)}")
end
```

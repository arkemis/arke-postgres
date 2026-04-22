# Reference — Public API Surface

Function-by-function reference for the modules you're likely to touch. Signatures reflect arke_postgres 0.4.1 source. For each module, only public functions that callers use are listed; internal helpers are omitted.

## Module map

| Module | Role |
|---|---|
| `ArkePostgres` | Public CRUD API + project management + initialization |
| `ArkePostgres.Application` | OTP supervisor, starts Repo and runs init |
| `ArkePostgres.Repo` | Ecto.Repo (Postgres adapter) |
| `ArkePostgres.Query` | Query building, execution, link CTE, boot-time loading |
| `ArkePostgres.ArkeUnit` | JSONB-mode CRUD + data encoding/decoding |
| `ArkePostgres.Table` | Relational-mode CRUD |
| `ArkePostgres.Tables.ArkeUnit` | Ecto schema: `arke_unit` table |
| `ArkePostgres.ArkeLink` | Ecto schema: `arke_link` table |
| `ArkePostgres.Tables.ArkeSchema` | Ecto schema: `arke_schema` table |
| `ArkePostgres.Tables.ArkeField` | Ecto schema: `arke_field` table |
| `ArkePostgres.Tables.ArkeSchemaField` | Ecto schema: `arke_schema_field` join table |
| `Mix.Tasks.ArkePostgres.CreateProject` | CLI: create project schema + arke_project unit |
| `Mix.Tasks.ArkePostgres.CreateMember` | CLI: create super_admin member for a project |

---

## `ArkePostgres` — main module

The public API wired into Arke's persistence config.

### Initialization

```elixir
ArkePostgres.init()
# -> :ok | :error
```
Validates env vars, loads all projects from `arke_system`, bootstraps ETS managers for each project. Called by `Application.start/2`. Returns `:error` and the application halts if DB is unreachable or env vars are missing.

```elixir
ArkePostgres.check_env()
# -> {:ok, nil} | {:error, [missing_keys]}
```
Checks for `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` in `System.get_env/1`.

```elixir
ArkePostgres.print_missing_env(keys)
# -> :ok
```
Prints red-highlighted error messages for each missing key.

### CRUD

```elixir
ArkePostgres.create(project :: atom, unit :: %Unit{})
# -> {:ok, %Unit{}} | {:error, errors}
```
Dispatches to `ArkeUnit.insert/3` (arke mode) or `Table.insert/3` (table mode) based on `arke.data.type`. On success, merges `%{project: project}` into the unit's metadata. On failure, formats changeset errors.

```elixir
ArkePostgres.update(project :: atom, unit :: %Unit{})
# -> {:ok, %Unit{}}
```
Dispatches to `ArkeUnit.update/3` or `Table.update/4`. For table mode, separates primary-key fields (used in WHERE) from non-PK fields (used in SET).

```elixir
ArkePostgres.delete(project :: atom, unit :: %Unit{})
# -> {:ok, nil} | {:error, errors}
```
Dispatches to `ArkeUnit.delete/3` or `Table.delete/3`.

### Project management

```elixir
ArkePostgres.create_project(%Unit{arke_id: :arke_project, id: id})
# -> :ok | :error
```
Runs `CREATE SCHEMA "id"` then `Ecto.Migrator.run(Repo, :up, all: true, prefix: id)`. Catches `DBConnection.ConnectionError` and `Postgrex.Error`.

```elixir
ArkePostgres.delete_project(%Unit{arke_id: :arke_project, id: id})
# -> {:ok, result} | {:error, reason}
```
Runs `DROP SCHEMA "id" CASCADE`.

### Helpers

```elixir
ArkePostgres.data_as_klist(data :: map)
# -> keyword_list
```
Converts a map to a keyword list via `Enum.to_list/1`.

---

## `ArkePostgres.Query`

Query building, execution, and boot-time data loading.

### Query execution

```elixir
Query.execute(query :: %Arke.Core.Query{}, :all)
# -> [%Unit{}, ...]
```
Generates SQL, executes with `Repo.all(prefix: project)`, converts records to Units.

```elixir
Query.execute(query, :one)
# -> %Unit{} | nil
```
Single record. Returns `nil` if not found.

```elixir
Query.execute(query, :count)
# -> integer
```
Count query — strips order, applies `count("*")`.

```elixir
Query.execute(query, :raw)
# -> {sql_string, params}
```
Returns the SQL string and parameters via `Ecto.Adapters.SQL.to_sql/3`. Does not execute.

```elixir
Query.execute(query, :pseudo_query)
# -> %Ecto.Query{}
```
Returns the built Ecto query struct without executing.

### Query building

```elixir
Query.generate_query(arke_query :: %Arke.Core.Query{}, action :: atom)
# -> %Ecto.Query{}
```
Translates an Arke query into an Ecto query. Pipeline: `base_query → handle_paths_join → handle_filters → handle_orders → handle_offset → handle_limit`.

### Column mapping

```elixir
Query.get_column(parameter)
Query.get_column(parameter, join_alias)
# -> Ecto.Query.dynamic()
```
Returns an Ecto dynamic expression for accessing a parameter's value in SQL. Dispatches on `persistence`:
- `"table_column"` → `field(q, :column_name)`
- `"arke_parameter"` → `fragment("(? -> ? ->> 'value')::TYPE", field(q, :data), param_id)` with type-specific casts

Type cast mapping:

| Parameter type | SQL cast |
|---|---|
| `:string`, `:atom`, `:link`, `:dynamic` | `::text` |
| `:integer` | `::integer` |
| `:float` | `::float` |
| `:boolean` | `::boolean` |
| `:datetime` | `::timestamp` |
| `:date` | `::date` |
| `:time` | `::time` |
| `:dict`, `:list` | `::JSON` |
| `multiple: true` (any) | `::jsonb` |

### Filter operators

`filter_query_by_operator/4` translates Arke filter operators to SQL:

| Operator | SQL |
|---|---|
| `:eq` | `= value` (or `jsonb_exists()` for `multiple: true`) |
| `:contains` | `LIKE '%value%'` |
| `:icontains` | `ILIKE '%value%'` |
| `:startswith` | `LIKE 'value%'` |
| `:istartswith` | `ILIKE 'value%'` |
| `:endswith` | `LIKE '%value'` |
| `:iendswith` | `ILIKE '%value'` |
| `:lt` | `< value` |
| `:lte` | `<= value` |
| `:gt` | `> value` |
| `:gte` | `>= value` |
| `:in` | `IN (values)` |
| `:isnull` | `IS NULL` (with `data \? 'key'` check to distinguish null from missing) |

### Link traversal

```elixir
Query.get_nodes(project, action, unit_id_list, depth, direction, type)
# -> %Ecto.Query{}  (with recursive CTE)
```
Builds a recursive CTE query that walks the `arke_link` graph. `direction` is `:child` or `:parent`. `type` filters by link type (e.g. `"parameter"`, `"group"`, `"link"`) or `nil` for all types.

### Boot-time loading

```elixir
Query.get_project_record()
# -> [%{id: _, arke_id: "arke_project", ...}, ...]
```
Fetches all `arke_project` units from the `arke_system` schema.

```elixir
Query.get_manager_units(project_id :: atom)
# -> {parameters, arke_list, groups}
```
Loads all parameters, arkes, and groups for a project from the DB. Fetches `arke_link` records (type `"parameter"` or `"group"`), joins metadata, parses into the data structures `Arke.handle_manager/3` expects.

### Record to Unit conversion

```elixir
Query.init_unit(record, arke, project)
# -> %Unit{}
```
Converts a database record (map with `:id`, `:arke_id`, `:data`, `:metadata`, `:inserted_at`, `:updated_at`) into an `Arke.Core.Unit` by resolving the Arke definition, extracting JSONB data, and calling `Arke.Core.Unit.load/2`.

---

## `ArkePostgres.ArkeUnit`

JSONB-mode persistence. All functions operate on the `arke_unit` table.

```elixir
ArkeUnit.insert(project, arke, unit)
# -> {:ok, record} | {:error, changeset_errors}
```
Encodes unit data via `encode_unit_data/2`, inserts via `Repo.insert` with the `ArkePostgres.Tables.ArkeUnit` changeset. ID auto-generated as UUID if nil.

```elixir
ArkeUnit.update(project, arke, unit, where \\ [])
# -> {count, nil}
```
Encodes data, runs `Repo.update_all` with `WHERE arke_id = ? AND id = ?`.

```elixir
ArkeUnit.delete(project, arke, unit)
# -> {:ok, nil} | {:error, "item not found"}
```
Runs `Repo.delete_all` with `WHERE arke_id = ? AND id = ?`. Returns error if zero rows affected.

### Encoding / Decoding

```elixir
ArkeUnit.encode_unit_data(arke, data :: map)
# -> %{"field_id" => %{value: X, datetime: T}, ...}
```
Wraps each field value with a timestamp. Skips parameters with `only_runtime: true`.

```elixir
ArkeUnit.decode_unit_data(data :: map)
# -> %{"field_id" => value, ...}
```
Unwraps — extracts `"value"` from each entry.

```elixir
ArkeUnit.format_arke_unit_record(record :: map)
# -> keyword_list
```
Converts a DB record map to a keyword list, unwrapping the `data` JSONB into top-level keys.

---

## `ArkePostgres.Table`

Relational-mode persistence. Operates on tables named after the Arke's `id`.

```elixir
Table.get_all(project, schema, fields, where \\ [])
# -> [records]
```
`Repo.all` with dynamic table name, field selection, and optional WHERE.

```elixir
Table.get_by(project, schema, fields, where)
# -> record | nil
```
`Repo.one` — single record.

```elixir
Table.insert(project, schema, data)
# -> {count, nil}
```
`Repo.insert_all` — bulk-capable.

```elixir
Table.update(project, schema, data, where \\ [])
# -> {count, nil}
```
`Repo.update_all` — SET from `data`, WHERE from `where`.

```elixir
Table.delete(project, schema, where)
# -> {:ok, nil} | {:error, "item not found"}
```
`Repo.delete_all`. Returns error if zero rows affected.

---

## Ecto Schemas

### `ArkePostgres.Tables.ArkeUnit`

```elixir
@primary_key {:id, :string, []}
schema "arke_unit" do
  field :arke_id, :string
  field :data, :map
  field :metadata, :map, default: %{}
  timestamps()
end
```

`changeset/1` validates required fields (`:id`, `:arke_id`, `:data`, `:metadata`) and a unique constraint on `:id`.

### `ArkePostgres.ArkeLink`

```elixir
@foreign_key_type :string
schema "arke_link" do
  field :type, :string, default: "link"
  belongs_to :parent_id, ArkePostgres.ArkeUnit, primary_key: true
  belongs_to :child_id, ArkePostgres.ArkeUnit, primary_key: true
  field :metadata, :map, default: %{}
end
```

`changeset/1` validates required fields (`:type`, `:parent_id`, `:child_id`, `:metadata`).

### `ArkePostgres.Tables.ArkeSchema`

Fields: `id` (string PK), `label`, `type` (default `"arke"`), `active` (boolean), `metadata` (map), timestamps.

### `ArkePostgres.Tables.ArkeField`

Fields: `id` (string PK), `label`, `type` (default `"string"`), `format` (default `"attribute"`), `is_primary` (boolean), `metadata` (map), timestamps.

### `ArkePostgres.Tables.ArkeSchemaField`

Join table: `arke_schema_id` (FK, composite PK), `arke_field_id` (FK, composite PK), `metadata` (map).

---

## Mix tasks

### `mix arke_postgres.create_project`

```bash
mix arke_postgres.create_project --id my_project
mix arke_postgres.create_project --id my_project --label "My Project" --description "A description"
```

Options:
- `--id` (required) — project identifier, becomes the PostgreSQL schema name
- `--label` — human-readable label (defaults to capitalized id)
- `--description` — project description

Process:
1. Validates env vars.
2. Starts `ArkePostgres.Repo`.
3. Creates PostgreSQL schema via `ArkePostgres.create_project/1`.
4. Inserts an `arke_project` unit in the `arke_system` schema.

### `mix arke_postgres.create_member`

```bash
mix arke_postgres.create_member --project my_project --username admin --password secret
mix arke_postgres.create_member --project my_project
# defaults to username: admin, password: admin
```

Options:
- `--project` (required) — target project
- `--username` — defaults to `"admin"`
- `--password` — defaults to `"admin"`
- `--email` — defaults to `"username@bar.com"`

Process:
1. Checks if user with that username exists in `:arke_system`.
2. Creates user if missing.
3. Creates `super_admin` member in the target project.

Requires `arke_auth` to be available (starts `:arke_auth` application).

---

## What's NOT in this package

Search elsewhere for:
- Query DSL, filter operators, `QueryManager` API → `arke` core
- Schema definitions, validation, lifecycle hooks → `arke` core
- HTTP routes, controllers, REST conventions → `arke_server`
- Authentication, JWT, permissions → `arke_auth`
- React/Next.js UI components → frontend packages

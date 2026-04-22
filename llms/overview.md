# Overview — Mental Model

## What problem ArkePostgres solves

Arke core defines a dynamic schema system with CRUD pipelines, validation, and query building — but it does no I/O. The persistence layer is injected via function references. ArkePostgres is the production implementation of that seam: it translates Arke's domain model into PostgreSQL operations, and at boot, loads persisted schema definitions back into Arke's ETS managers.

Without ArkePostgres (or an equivalent adapter), Arke is a schema engine with no storage.

## The four core responsibilities

### 1. CRUD persistence

`ArkePostgres.create/2`, `update/2`, `delete/2` are the functions wired into Arke's `persistence` config. When `Arke.QueryManager.create/3` finishes validation and hooks, it calls `ArkePostgres.create(project, unit)` to persist the Unit.

The adapter supports two persistence modes based on the Arke's `type` field:

- **`"arke"` mode** (default) — Units are stored in the `arke_unit` table as JSONB. Field values go into a `data` column as `{"field_id": {"value": X, "datetime": T}}` entries. This is the flexible, schema-less path.
- **`"table"` mode** — Units are stored in a dedicated relational table matching the Arke's `id`. Each parameter maps to a column. This is the traditional relational path, used when you need direct SQL access or foreign keys.

The routing is automatic: `ArkePostgres.create/2` reads `arke.data.type` and dispatches to `ArkeUnit.insert/3` or `Table.insert/3`.

### 2. Query execution

`ArkePostgres.Query.execute/2` takes an `%Arke.Core.Query{}` struct and returns results. The pipeline:

```
%Arke.Core.Query{filters, orders, offset, limit, link}
  → generate_query(arke_query, action)
    → base_query()                    # SELECT from arke_unit or CTE for link queries
    → handle_paths_join(paths)        # LEFT JOIN for nested filter paths
    → handle_filters(filters)         # WHERE clauses with JSONB-aware fragments
    → handle_orders(orders)           # ORDER BY with type-cast fragments
    → handle_offset(offset)           # OFFSET
    → handle_limit(limit)             # LIMIT
  → Repo.all/one/aggregate            # Execute against the project's schema
  → generate_units(records)           # Convert DB records back to %Unit{} structs
```

The query engine handles type-specific SQL casting. For `arke_parameter` persistence, field access is via JSONB fragments like `(data -> 'name' ->> 'value')::text`. Each parameter type (`:string`, `:integer`, `:float`, `:boolean`, `:datetime`, `:date`, `:time`, `:dict`, `:list`, `:link`, `:dynamic`) gets its own cast.

### 3. Boot-time initialization

When `ArkePostgres.Application` starts, it:

1. Starts `ArkePostgres.Repo` (Ecto connection pool).
2. Calls `ArkePostgres.init/0` which:
   - Validates that `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` env vars exist.
   - Loads all `arke_project` units from the `arke_system` schema.
   - For each project (`:arke_system` first), calls `Query.get_manager_units/1` to load parameters, arkes, and groups from the DB.
   - Passes them to `Arke.handle_manager/3` to populate the ETS tables.
3. If init fails (missing env vars, DB connection error), the system halts.

This is how Arke "knows" about runtime-defined schemas: ArkePostgres reads them from PostgreSQL and feeds them into the ETS managers.

### 4. Multi-tenant schema management

ArkePostgres uses **PostgreSQL schemas** for project isolation. Each Arke project maps to a PostgreSQL schema:

- `arke_system` — the shared/default schema containing system Arkes, Parameters, Groups, and all project definitions.
- `my_project` — a tenant-specific schema with its own `arke_unit` and `arke_link` tables.

`ArkePostgres.create_project/1` runs `CREATE SCHEMA "project_id"` followed by `Ecto.Migrator.run` with the new schema as prefix. `ArkePostgres.delete_project/1` runs `DROP SCHEMA "project_id" CASCADE`.

All Ecto queries use `prefix: project_id` to target the correct schema.

## Database schema

The initial migration (`20220610104406_initial_migration.exs`) creates two tables per schema:

### `arke_unit` — universal record storage

| Column | Type | Notes |
|---|---|---|
| `id` | `string` | Primary key |
| `arke_id` | `string` | NOT NULL; which Arke this Unit is an instance of |
| `data` | `map` (JSONB) | NOT NULL, default `{}`; field values as `{"field_id": {"value": X, "datetime": T}}` |
| `metadata` | `map` (JSONB) | NOT NULL, default `{}`; project ref, custom metadata |
| `inserted_at` | `timestamp` | Auto-managed |
| `updated_at` | `timestamp` | Auto-managed |

### `arke_link` — relationship storage

| Column | Type | Notes |
|---|---|---|
| `type` | `string` | NOT NULL, default `"link"`; discriminator (`"parameter"`, `"group"`, `"link"`) |
| `parent_id` | `string` (FK → arke_unit.id) | Composite PK; `ON DELETE CASCADE` |
| `child_id` | `string` (FK → arke_unit.id) | Composite PK; `ON DELETE CASCADE` |
| `metadata` | `map` (JSONB) | Default `{}` |

Indexed on `parent_id` and `child_id`.

## Link traversal — recursive CTE

When Arke queries include a link filter (e.g. "find all children of unit X up to depth 3"), ArkePostgres generates a recursive CTE:

```sql
WITH RECURSIVE tree(depth, parent_id, type, child_id, metadata, starting_unit) AS (
  -- Base case: direct links from the starting unit(s)
  SELECT 0, parent_id, type, child_id, metadata, <link_field>
  FROM <project>.arke_link
  WHERE <link_field> = ANY(<unit_ids>)
  UNION
  -- Recursive: walk further along the graph
  SELECT depth + 1, arke_link.parent_id, arke_link.type, arke_link.child_id,
         arke_link.metadata, tree.starting_unit
  FROM <project>.arke_link
  JOIN tree ON arke_link.<link_field> = tree.<tree_field>
  WHERE depth < <max_depth>
)
SELECT * FROM tree ORDER BY depth
```

The direction (`:child` or `:parent`) controls which field is the link field vs tree field: `:child` walks `parent_id → child_id`, `:parent` walks `child_id → parent_id`. An optional `type` filter restricts to specific link types.

The CTE result is joined with `arke_unit` to return full Unit records with link metadata (depth, link type, starting unit).

## Data encoding

When a Unit is persisted in arke mode, each field value is wrapped:

```elixir
# In-memory Unit
%Unit{data: %{name: "Ada", age: 36}}

# ↓ encode_unit_data/2

# In DB (arke_unit.data column)
%{
  "name" => %{"value" => "Ada", "datetime" => "2026-01-15T10:30:00Z"},
  "age"  => %{"value" => 36,    "datetime" => "2026-01-15T10:30:00Z"}
}

# ↓ init_unit (on read)

# Back to in-memory Unit
%Unit{data: %{name: "Ada", age: 36}}
```

Parameters with `only_runtime: true` are skipped during encoding — they exist only in memory.

## Architecture at a glance

```
┌─────────────────────────────────────────────────────┐
│            Arke Core (QueryManager, etc.)            │
│         persistence: %{arke_postgres: %{...}}        │
└───────────────┬─────────────────────────────────────┘
                │  create/2, update/2, delete/2,
                │  execute_query/2, create_project/1
                ▼
     ┌────────────────────┐
     │    ArkePostgres     │   ◄── dispatch by arke type
     └─────────┬──────────┘
               │
       ┌───────┼────────┐
       ▼       ▼        ▼
  ┌────────┐ ┌───────┐ ┌──────────────┐
  │ArkeUnit│ │Table  │ │Query         │
  │(JSONB) │ │(relat)│ │(SQL builder) │
  └────┬───┘ └───┬───┘ └──────┬───────┘
       │         │             │
       └─────────┴─────────────┘
                 │
          ┌──────┴──────┐
          │ArkePostgres │
          │  .Repo      │   ◄── Ecto.Repo (Postgres adapter)
          └──────┬──────┘
                 │
          ┌──────┴──────┐
          │ PostgreSQL   │
          │ (per-schema) │
          └─────────────┘
```

## Module map

| Module | Role |
|---|---|
| `ArkePostgres` | Public API: `create/2`, `update/2`, `delete/2`, `create_project/1`, `delete_project/1`, `init/0` |
| `ArkePostgres.Application` | OTP supervisor; starts Repo, runs init |
| `ArkePostgres.Repo` | Ecto.Repo configuration |
| `ArkePostgres.Query` | Query building, execution, CTE link traversal, boot-time data loading |
| `ArkePostgres.ArkeUnit` | JSONB-mode CRUD (`insert/3`, `update/3`, `delete/3`, encoding/decoding) |
| `ArkePostgres.Table` | Relational-mode CRUD (`get_all/4`, `get_by/4`, `insert/3`, `update/4`, `delete/3`) |
| `ArkePostgres.Tables.ArkeUnit` | Ecto schema for `arke_unit` table |
| `ArkePostgres.ArkeLink` | Ecto schema for `arke_link` table |
| `ArkePostgres.Tables.ArkeSchema` | Ecto schema for `arke_schema` table |
| `ArkePostgres.Tables.ArkeField` | Ecto schema for `arke_field` table |
| `ArkePostgres.Tables.ArkeSchemaField` | Ecto schema for `arke_schema_field` join table |
| `Mix.Tasks.ArkePostgres.CreateProject` | Mix task: create a new project (schema + arke_project unit) |
| `Mix.Tasks.ArkePostgres.CreateMember` | Mix task: create a super_admin member for a project |

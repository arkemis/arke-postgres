# Gotchas — Sharp Edges

Operational surprises you'll hit when working with arke_postgres. These are distinct from design rationale (see [design.md](design.md) for the "why"); this file is the "what trips people up."

---

## Env vars are checked at boot and halt the system

`ArkePostgres.init/0` checks for `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD` via `System.get_env/1`. If any are missing, it prints errors and returns `:error`. `Application.start/2` then calls `System.halt(0)`.

**Symptom:** the application starts and immediately exits with no stack trace — just red "env key X not found" messages.

**Surprises:**
- The halt code is `0` (success), not `1`. Process supervisors that check exit codes may think the app exited cleanly.
- The check happens at runtime, not compile time. The app compiles fine without these vars — it crashes on start.
- There's no retry or graceful degradation. A transient env issue at boot is fatal.

**What to do:** ensure all four env vars are set before the application starts. In Docker/Kubernetes, set them in the container spec. In dev, use a `.env` file or `direnv`. If you need to run mix tasks that don't require DB access, set dummy values.

---

## JSONB value wrapper — `data->'field'->> 'value'`, not `data->>'field'`

All field values in the `arke_unit.data` column are wrapped: `{"field_id": {"value": X, "datetime": T}}`.

**Symptom:** raw SQL queries return `nil` when you expect a value, because you wrote `data->>'name'` instead of `data->'name'->>'value'`.

**What to do:** always access values via `data -> 'field_name' ->> 'value'`. If you need the modification timestamp, use `data -> 'field_name' ->> 'datetime'`. The Arke query DSL handles this automatically — this only matters for raw SQL or direct Repo queries.

See [design.md](design.md#why-the-valuedatetime-wrapper-in-jsonb) for why this wrapper exists.

---

## `multiple: true` parameters use `jsonb_exists()` for equality

When a parameter has `multiple: true`, its value is stored as a JSONB array. The `:eq` operator uses `jsonb_exists(column, value)` instead of `column = value`.

**Symptom:** equality filters on multi-value parameters behave like "contains" — `name__eq: "admin"` matches `["admin", "user"]`.

**What to do:** this is by design. For multi-value parameters, `:eq` means "the array contains this value". Use `:in` if you need exact array matching (though this isn't supported for JSONB arrays in the current implementation).

---

## Null checks distinguish "null value" from "missing key"

The `:isnull` operator generates:

```sql
-- isnull: false (field IS null but key exists in data)
data->'name'->>'value' IS NULL AND data ? 'name'

-- isnull: true (negate: key may not exist)
data->'name'->>'value' IS NULL
```

**Symptom:** filtering for `name__isnull: true` returns Units where `name` was never set *and* Units where `name` was explicitly set to `nil`. Filtering for `name__isnull: false` (negate) returns only Units where the key exists in the JSONB but the value is null.

**What to do:** be aware that JSONB "key missing" and "key present with null value" are different things. If you need to distinguish them, you may need a raw SQL query with `data ? 'key'`.

---

## Table-mode Arkes require manual migrations

When an Arke has `type: "table"`, ArkePostgres expects a real PostgreSQL table matching the Arke's `id`. The adapter doesn't auto-create these tables.

**Symptom:** `Postgrex.Error: relation "my_table" does not exist` when creating/querying a table-mode Arke.

**What to do:** write an Ecto migration that creates the table with columns matching the Arke's parameters. Remember: the migration runs per-schema (per-project), so the table is created inside each project's PostgreSQL schema.

---

## `DROP SCHEMA CASCADE` is the only project deletion path

`ArkePostgres.delete_project/1` runs `DROP SCHEMA "id" CASCADE`. This is irreversible — all tables, data, indexes, and functions in the schema are destroyed.

**Symptom:** deleted project's data is unrecoverable.

**What to do:** backup the schema before deletion if you might need the data. There's no soft-delete, archive, or "move to trash" at the adapter level.

---

## Changeset error formatting loses structure

`ArkePostgres.create/2` catches changeset errors and formats them via `handle_changeset_errors/1`, which joins field names and messages into strings like `"id: has already been taken"`.

**Symptom:** error handling code that expects structured `{field, {message, opts}}` tuples gets strings instead.

**What to do:** if you need structured errors, catch them at the `ArkeUnit.insert/3` level before they pass through `ArkePostgres.create/2`. Or parse the string format — it's consistent.

---

## `literal/1` in CTE queries interpolates directly into SQL

The recursive CTE for link traversal uses `literal/1` to interpolate the project schema name and field names directly into the SQL string:

```elixir
literal(^project)      # schema name
literal(^link_field)   # "parent_id" or "child_id"
literal(^tree_field)   # the opposite field
```

**Symptom:** not a typical user-facing issue, but important for security review. `literal/1` bypasses Ecto's parameterization.

**What to do:** ensure project IDs and link fields come from trusted sources (they do in normal Arke usage — project IDs come from the DB, field names are hardcoded strings). Don't construct `get_nodes` calls with user-provided project names without sanitization.

---

## `update/2` always returns `{:ok, unit}` (no error path for arke mode)

`ArkePostgres.update/2` pattern-matches `{:ok, unit} = handle_update(...)`. In arke mode, `ArkeUnit.update/3` calls `Repo.update_all` which returns `{count, nil}` — it never returns an error tuple, even if zero rows were updated.

**Symptom:** updating a non-existent Unit succeeds silently. No `{:error, _}` is returned.

**What to do:** if you need to verify the update affected a row, check the return from `Repo.update_all` directly. The Arke core pipeline typically validates the Unit exists before calling update, so this rarely manifests in practice.

---

## `delete/3` returns error on "item not found" but doesn't distinguish why

Both `ArkeUnit.delete/3` and `Table.delete/3` check if `Repo.delete_all` affected zero rows and return `{:error, "item not found"}`. But zero rows could mean:
- The Unit genuinely doesn't exist.
- The `arke_id` or `id` was wrong (typo, atom vs string mismatch).
- The Unit exists in a different project schema.

**What to do:** if you get "item not found" unexpectedly, verify the Unit's `id` and `arke_id` match what's in the DB, and that you're targeting the correct project.

---

## `get_manager_units` uses `String.to_atom` — unbounded atom creation

`Query.get_manager_units/1` converts string IDs from the database to atoms: `String.to_atom(p.child_id)`, `String.to_atom(k)` for metadata keys.

**Symptom:** not a crash, but a potential atom table leak. Every unique parameter ID, metadata key, and arke ID loaded from the DB becomes a permanent atom.

**What to do:** this is acceptable in practice because the number of schema definitions (arkes, parameters, groups) is bounded and small. But if you're dynamically creating thousands of arke definitions at runtime, be aware of atom table pressure.

---

## Boot order matters — `arke_system` must load first

`ArkePostgres.init/0` sorts projects so `arke_system` loads first. If this sort is removed or broken, tenant projects may fail to initialize because their arke definitions reference system types that aren't in ETS yet.

**Symptom:** `ArkeManager.get(:arke, project)` returns `nil` during initialization of a tenant project, causing downstream failures.

**What to do:** don't modify the project loading order in `init/0`. If you're debugging boot issues, check that `arke_system` has its parameters, arkes, and groups loaded before any tenant project tries to reference them.

---

## `create_project/1` only matches `arke_id: :arke_project`

The `ArkePostgres.create_project/1` function pattern-matches on `%{arke_id: :arke_project}`. Passing a Unit with any other `arke_id` silently returns `nil`.

**Symptom:** calling `create_project` with a non-project Unit does nothing — no error, no schema created.

**What to do:** always pass a proper project Unit. If you're calling `create_project` manually (outside the normal `QueryManager.create` pipeline), ensure the Unit has `arke_id: :arke_project`.

# Design — Why It's Shaped This Way

Rationale behind the load-bearing decisions in arke_postgres. Useful for:
- **Devs** making sense of unexpected behavior ("it's this way because...")

These are architectural commitments. Changing them would cascade through the adapter and its integration with Arke core.

---

## Why PostgreSQL schemas for multi-tenancy

**The choice:** each Arke project maps to a PostgreSQL schema. `arke_system` is always present; tenant projects get their own schema via `CREATE SCHEMA`. All queries use Ecto's `prefix:` option to target the correct schema.

**What this buys:**
- Strong isolation at the database level — a query against `:my_project` physically cannot touch `:other_project`'s tables without an explicit cross-schema reference.
- Standard PostgreSQL tooling works: `pg_dump` per schema, per-schema permissions, per-schema `search_path` for direct SQL access.
- Migrations run once per schema via `Ecto.Migrator.run/3` with `prefix:`. Every project gets the same table structure.
- Clean provisioning: `CREATE SCHEMA` + run migrations = project ready. No row-level filtering to maintain.

**The cost:**
- Schema count scales linearly with tenants. PostgreSQL handles thousands of schemas, but operational tooling (migrations, backups) becomes slower.
- `DROP SCHEMA CASCADE` is the only teardown — there's no soft-delete or archive path at the adapter level.
- Cross-project queries require explicit multi-schema SQL. The adapter doesn't support them.
- Connection pool is shared across all schemas — no per-tenant pool isolation.

**Compared to row-level tenancy:** row-level would put all tenants in one table set with a `project_id` column. Simpler migrations, easier cross-tenant analytics, but requires careful WHERE-clause discipline on every query. Schema isolation was chosen for its stronger guarantees.

---

## Why dual persistence modes (arke vs table)

**The choice:** Units can be stored in two ways depending on `arke.data.type`:
- `"arke"` → JSONB in the `arke_unit` table (the default).
- `"table"` → a dedicated relational table with one column per parameter.

**What this buys:**
- The JSONB path supports Arke's core value proposition: dynamic schemas without migrations. Adding a parameter to an Arke doesn't require a DDL change.
- The table path supports performance-critical models where direct column access, indexes, foreign keys, and standard SQL JOINs are needed.
- The routing is transparent to Arke core — `ArkePostgres.create/2` dispatches based on `arke.data.type`. The caller doesn't know which storage mode is used.

**The cost:**
- Two code paths for every CRUD operation. `ArkeUnit` and `Table` modules are parallel implementations with different semantics.
- Table-mode Arkes require manual migrations. There's no auto-DDL from parameter definitions.
- Querying across both modes in a single query isn't supported — you can't JOIN an `arke_unit` JSONB record with a `"table"` record in one Arke query.
- The JSONB path trades query performance for flexibility. Filtering on `data->'field'->> 'value'` is slower than a direct column scan, even with GIN indexes.

**When to revisit:** if a hybrid mode (some fields in columns, some in JSONB) becomes necessary, the `persistence: "table_column"` vs `"arke_parameter"` distinction on individual parameters already provides the metadata — but the query engine would need a mixed-mode handler.

---

## Why the value+datetime wrapper in JSONB

**The choice:** each field value in the `data` JSONB column is stored as `{"value": X, "datetime": T}`, not as a bare value.

**What this buys:**
- Per-field modification tracking. You know not just *what* a field's value is, but *when* it was last set. Useful for conflict resolution, auditing, and sync.
- The `datetime` can be used for incremental sync (fetch fields changed since time T) without requiring a separate audit table.

**The cost:**
- Every JSONB access requires an extra level of nesting: `data->'name'->>'value'` instead of `data->>'name'`. This is baked into every SQL fragment in `query.ex`.
- Storage overhead: roughly 30-50 bytes per field for the wrapper and timestamp.
- The wrapper shape is not optional — all encode/decode paths assume it. Raw JSONB queries must know the structure.

**Compared to bare values:** bare values would simplify SQL fragments significantly, but you'd lose per-field timestamps and need a separate mechanism for change tracking.

---

## Why init halts the system on failure

**The choice:** `ArkePostgres.Application.start/2` calls `ArkePostgres.init/0`. If init returns `:error` (missing env vars, DB connection failure, Postgrex errors), `System.halt(0)` is called.

**What this buys:**
- Fail-fast: the application never starts in a broken state. If the database is unreachable, you find out immediately, not when the first request hits.
- Clear error messages: missing env vars are enumerated before halt.
- No partially-initialized managers: either all projects are loaded or none are.

**The cost:**
- No graceful degradation. A transient DB issue at boot kills the application. A retry strategy would allow recovery.
- `System.halt(0)` exits with success status code (0), which can confuse process supervisors expecting non-zero on failure.
- No way to start the app without a database (e.g. for running non-DB mix tasks).

**When to revisit:** adding a retry-with-backoff on DB connection would be low-cost. Changing the halt code to non-zero would be a one-line fix.

---

## Why Ecto queries use raw fragments extensively

**The choice:** `ArkePostgres.Query` builds Ecto queries using `fragment/1` for nearly all JSONB field access, type casting, and the recursive CTE. Very little uses Ecto's schema-based query API.

**What this buys:**
- Full control over the generated SQL. JSONB access patterns (`data -> 'key' ->> 'value'`) and type casts (`::integer`, `::timestamp`) don't have Ecto schema equivalents.
- The recursive CTE for link traversal is raw SQL by necessity — Ecto doesn't support recursive CTEs in its query DSL.
- Type-specific casting ensures PostgreSQL can use indexes and apply correct comparison semantics (e.g. timestamp comparison vs string comparison).

**The cost:**
- The query code is complex and hard to read. Each parameter type has a dedicated `get_arke_column/2` clause with a `dynamic` + `fragment` combination.
- SQL injection surface is mitigated by Ecto's parameterization, but the `literal/1` calls in the CTE (for schema name and field names) interpolate directly into SQL.
- Testing requires a real PostgreSQL instance — you can't mock the fragment behavior.

**Compared to schema-based queries:** impossible here. The `arke_unit` table is a single table storing all Unit types with JSONB — there's no typed Ecto schema per Arke. Fragments are the only viable approach.

---

## Why project loading sorts arke_system first

**The choice:** in `ArkePostgres.init/0`, projects are sorted with `arke_system` first:
```elixir
projects |> Enum.sort_by(&(to_string(&1.id) == "arke_system"), :desc)
```

**What this buys:**
- System Arkes, Parameters, and Groups (defined in `arke_system`) are loaded into ETS before any tenant project. This matters because tenant-scoped lookups fall back to `:arke_system` — if system definitions aren't loaded yet, the fallback finds nothing and tenant initialization breaks.
- The bootstrap order mirrors the dependency: system types → tenant-specific types.

**The cost:**
- Minor: the sort is on every boot. Negligible for typical project counts.

---

## Decisions explicitly left flexible

- **Repo configuration** — standard Ecto repo config via `config :arke_postgres, ArkePostgres.Repo`. Pool size, SSL, timeout all configurable.
- **Migration strategy** — uses Ecto's standard migrator. Custom migrations can be added to `priv/repo/migrations/`.

---

## Decisions that are non-negotiable (by current design)

- **PostgreSQL as the only supported database.** The Ecto adapter is hardcoded to `Ecto.Adapters.Postgres`. The raw CTE SQL, JSONB fragments, and `CREATE SCHEMA` DDL are all PostgreSQL-specific.
- **The `arke_unit` + `arke_link` two-table model.** All arke-mode storage goes through these two tables. Removing either would require redesigning the query engine and link traversal.
- **The value+datetime wrapper in JSONB.** Every encode/decode and query fragment assumes this shape.

If a roadmap conversation touches any of these three, treat it as foundational work, not incremental.

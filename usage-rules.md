# Rules for working with ArkePostgres

## Understanding ArkePostgres

ArkePostgres is the PostgreSQL persistence adapter for the Arke framework. Arke
core is a runtime-defined schema engine that performs no I/O; it calls plain
function references injected through `config :arke, persistence: %{...}`.
ArkePostgres is the production implementation of that seam: it persists Arke
Units as JSONB rows in a universal `arke_unit` table (or as rows in dedicated
relational tables), translates Arke's query DSL into Ecto queries with
JSONB-aware fragments and recursive-CTE link traversal, provisions one
PostgreSQL schema per Arke project (multi-tenancy via Ecto `prefix:`), and at
boot loads every project's parameters, arkes and groups into Arke's ETS
managers.

It is not an ORM, not a query builder and not a validation layer — those live
in `arke` core. It is PostgreSQL-only by design (JSONB, recursive CTEs,
`CREATE SCHEMA`). Read the topic rules in `usage-rules/` before using it.

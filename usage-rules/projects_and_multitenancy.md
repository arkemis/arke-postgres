# Projects and multitenancy

- One Arke project = one PostgreSQL schema. Every repo call carries
  `prefix: project`. `arke_system` is the shared schema holding system arkes,
  parameters, groups and all `arke_project` units.
- Each schema contains the same two tables (from the single shipped
  migration): `arke_unit` (JSONB rows) and `arke_link` (edges with `parent_id`
  / `child_id` FKs, cascade delete).
- Create a project from the CLI, then ALWAYS seed it — creation alone does not
  seed:

  ```bash
  mix arke_postgres.create_project --id client_acme --label "ACME Corp"
  mix arke.seed_project --project client_acme
  ```

  or programmatically (this goes through the proper Arke lifecycle):

  ```elixir
  project_arke = Arke.Boundary.ArkeManager.get(:arke_project, :arke_system)
  {:ok, _} = Arke.QueryManager.create(:arke_system, project_arke,
    id: "client_acme", label: "ACME Corp")
  ```

- Deleting a project runs `DROP SCHEMA ... CASCADE`. It is irreversible and
  there is no soft delete — treat it as a destructive operation and back up
  first.
- Project ids are interpolated into DDL (`CREATE SCHEMA "id"`) and into
  recursive-CTE SQL without parameterization — never feed user-controlled
  strings as project ids; validate/allowlist them.
- `create_project/1` and `delete_project/1` only match maps with
  `arke_id: :arke_project`; anything else silently does nothing (returns
  `nil`). Do not call them with bare ids.
- Boot order matters: `arke_system` must be loaded first (the `init/0` sort
  guarantees it). Do not reorder or bypass `ArkePostgres.init/0`.
- There are no cross-project queries — the adapter always targets exactly one
  schema. Aggregating across tenants requires your own SQL per schema.
- The connection pool is shared across all schemas; there is no per-tenant
  pool sizing or isolation.

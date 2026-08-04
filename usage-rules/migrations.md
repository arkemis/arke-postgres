# Migrations

- The package ships exactly one migration (creating `arke_unit` and
  `arke_link`). It runs automatically for every new project schema during
  `create_project`.
- Custom migrations go in `priv/repo/migrations/` and are plain
  `use Ecto.Migration` modules. Never hardcode a `prefix:` inside them — the
  migrator supplies the prefix per project schema.
- Run migrations manually against one schema with:

  ```elixir
  Ecto.Migrator.run(ArkePostgres.Repo, :up, all: true, prefix: "my_project")
  ```

  New migrations must be applied to EVERY existing project schema — loop over
  your projects.
- Arkes with `type: "table"` (relational mode) require hand-written
  migrations: there is no auto-DDL from parameter definitions. The symptom of
  a missing one is `Postgrex.Error: relation "my_table" does not exist`. The
  table name must equal the arke id.
- Never use the legacy Ecto schemas `ArkePostgres.Tables.ArkeSchema`,
  `.ArkeField`, `.ArkeSchemaField` and `ArkePostgres.ArkeLink` — their tables don't exist
  and their associations point at missing modules.

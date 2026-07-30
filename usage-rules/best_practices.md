# Best practices

- Call `ArkePostgres.create/update/delete` only through Arke core
  (`Arke.QueryManager`) — the adapter assumes units already validated and
  loaded, with atom ids. Direct calls with binary ids crash
  (`Atom.to_string/1`).
- `ArkePostgres.update/2` REPLACES the whole JSONB `data` column with the
  encoded unit. Updating with a partially-populated `%Unit{}` drops the
  missing fields. Use `Arke.QueryManager.update/2` (which loads first) or
  `update_key/2` for surgical `jsonb_set` writes.
- Update of a non-existent unit succeeds silently in JSONB mode
  (`Repo.update_all` returns `{0, nil}`) — verify existence first when it
  matters.
- `delete/2` returns `{:error, "item not found"}` on zero rows but cannot tell
  you why (missing unit vs wrong arke vs wrong project schema) — check the
  project/prefix before debugging the unit.
- Table-mode (`type: "table"`) create/update/delete swallow DB errors and
  return `{:ok, unit}` regardless — verify writes on relational arkes.
- Changeset errors are flattened into plain strings
  (`"id: id already exists"`); do not expect structured
  `{field, {msg, opts}}` tuples.
- Unsupported arke types make `ArkePostgres.update/2` raise `MatchError`
  instead of returning `{:error, _}` — only `"arke"` and `"table"` types
  exist.
- Boot loads DB content via `String.to_atom` — anyone who can write arbitrary
  rows to `arke_unit` can exhaust the atom table. Protect write access to the
  database.
- `mix arke_postgres.create_member` defaults to `admin`/`admin` with a fake
  email — always pass `--username/--password/--email` outside dev, and note it
  requires `--project` and the `:arke_auth` dep.
- Version pins are tight and load-bearing: `arke ~> 0.6.0` is a hard floor
  (`update_key` depends on it). Do not mix with older arke releases.
- Metadata round-trips are not byte-identical: the adapter injects
  `project:` into unit metadata on read and strips
  `"project" => "arke_system"` from parameter metadata for non-system
  projects. Don't diff stored vs loaded metadata literally.

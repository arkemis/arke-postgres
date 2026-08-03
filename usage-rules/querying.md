# Querying and the JSONB layout

- Normal querying goes through Arke core (`Arke.QueryManager`) — this package
  only translates. Reach for direct SQL/Ecto only as an escape hatch.
- The JSONB `data` column wraps every value:
  `%{"field" => %{"value" => x, "datetime" => ts}}`. In raw SQL always address
  values through the wrapper:

  ```sql
  -- WRONG: silently returns NULL
  SELECT * FROM my_project.arke_unit WHERE data->>'name' = 'Ada';

  -- CORRECT
  SELECT * FROM my_project.arke_unit WHERE data->'name'->>'value' = 'Ada';
  ```

- With direct Ecto always pass `prefix:` — omitting it hits the connection's
  default `search_path`, not your project:

  ```elixir
  ArkePostgres.Repo.all(
    from(u in "arke_unit",
      where: u.arke_id == "person",
      select: %{id: u.id, name: fragment("data -> 'name' ->> 'value'")}),
    prefix: "my_project")
  ```

- Debug generated SQL from the Arke side:

  ```elixir
  query(project: :p, arke: :person) |> where(name__eq: "ada") |> raw()          # {sql, params}
  query(project: :p, arke: :person) |> where(age__gte: 18) |> pseudo_query()    # Ecto query
  ```

- `:eq` on a `multiple: true` parameter compiles to `jsonb_exists/2` —
  equality behaves as "array contains". `:in` on JSONB arrays is not
  supported.
- `:isnull` distinguishes "key present with null value" from "key missing";
  its negated form checks only plain `IS NOT NULL`.
- Filter values that can't be cast to the parameter type make query building
  **raise** (`Parameter(...) value not valid`), not return an error tuple —
  sanitize filter input.
- Link traversal (`depth`, `direction`, `link_type`) compiles to a recursive
  CTE over `arke_link`; results carry `depth`, `link_metadata`, `link_type`
  and `starting_unit` alongside the unit columns.

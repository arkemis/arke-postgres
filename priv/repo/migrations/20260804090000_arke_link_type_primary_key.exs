defmodule ArkePostgres.Repo.Migrations.ArkeLinkTypePrimaryKey do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE #{table()} DROP CONSTRAINT arke_link_pkey")
    execute("ALTER TABLE #{table()} ADD PRIMARY KEY (type, parent_id, child_id)")
  end

  def down do
    execute("ALTER TABLE #{table()} DROP CONSTRAINT arke_link_pkey")
    execute("ALTER TABLE #{table()} ADD PRIMARY KEY (parent_id, child_id)")
  end

  # migrations run once per project schema, so the prefix has to come from the runner
  defp table, do: ~s("#{prefix() || "public"}".arke_link)
end

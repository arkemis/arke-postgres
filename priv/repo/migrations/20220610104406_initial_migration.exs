defmodule ArkePostgres.Repo.Migrations.InitialMigration do
  use Ecto.Migration

  def change do
    create table(:arke_unit, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:arke_id, :string, null: false)
      add(:data, :map, default: %{}, null: false)
      add(:metadata, :map, default: %{}, null: false)
      timestamps()
    end

    create table(:arke_link, primary_key: false) do
      add(:type, :string, default: "link", null: false, primary_key: true)

      add(:parent_id, references(:arke_unit, column: :id, type: :string, on_delete: :delete_all),
        primary_key: true
      )

      add(:child_id, references(:arke_unit, column: :id, type: :string, on_delete: :delete_all),
        primary_key: true
      )

      add(:metadata, :map, default: %{})
    end

    create(index(:arke_unit, :arke_id))
    create(index(:arke_link, :parent_id))
    create(index(:arke_link, :child_id))
  end
end

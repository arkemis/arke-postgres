defmodule ArkePostgres.Tables.ChangesetTest do
  use ExUnit.Case, async: true

  alias ArkePostgres.Tables

  describe "ArkeUnit.changeset/1" do
    defp unit_args, do: %{id: "u", arke_id: "a", data: %{}, metadata: %{}}

    test "accepts a complete row" do
      assert Tables.ArkeUnit.changeset(unit_args()).valid?
    end

    for field <- [:id, :arke_id, :data] do
      test "rejects a row missing #{field}" do
        changeset = Tables.ArkeUnit.changeset(Map.delete(unit_args(), unquote(field)))

        refute changeset.valid?
        assert {"can't be blank", _} = changeset.errors[unquote(field)]
      end
    end

    test "names the primary key constraint" do
      constraint =
        Tables.ArkeUnit.changeset(unit_args()).constraints
        |> Enum.find(&(&1.constraint == "arke_unit_pkey"))

      assert constraint.type == :unique
      assert constraint.error_message == "id already exists"
    end
  end

  describe "ArkeSchema.changeset/1" do
    test "rejects an empty row" do
      refute ArkePostgres.Tables.ArkeSchema.changeset(%{}).valid?
    end
  end
end

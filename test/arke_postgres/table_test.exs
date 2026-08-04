defmodule ArkePostgres.TableTest do
  @moduledoc """
  Exercises the raw table access layer against `test_schema.arke_unit`.
  """

  use ArkePostgres.RepoCase

  alias ArkePostgres.Table

  @schema %{id: :arke_unit}
  @fields [:id, :arke_id, :data, :metadata]

  defp row(id, data \\ %{}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    [
      id: id,
      arke_id: "table_test_arke",
      data: data,
      metadata: %{},
      inserted_at: now,
      updated_at: now
    ]
  end

  test "insert then get_by returns the row" do
    assert {1, _} = Table.insert(@project, @schema, row("table_insert"))

    row = Table.get_by(@project, @schema, @fields, id: "table_insert")

    assert row.id == "table_insert"
    assert row.arke_id == "table_test_arke"
  end

  test "get_by returns nil when nothing matches" do
    assert Table.get_by(@project, @schema, @fields, id: "table_absent") == nil
  end

  test "get_all returns every matching row" do
    Table.insert(@project, @schema, row("table_all_1"))
    Table.insert(@project, @schema, row("table_all_2"))

    ids =
      Table.get_all(@project, @schema, @fields, arke_id: "table_test_arke")
      |> Enum.map(& &1.id)
      |> Enum.sort()

    assert ids == ["table_all_1", "table_all_2"]
  end

  test "get_all with no match returns an empty list" do
    assert Table.get_all(@project, @schema, @fields, arke_id: "table_test_no_such_arke") == []
  end

  test "update changes only the matching row" do
    Table.insert(@project, @schema, row("table_update", %{"k" => "before"}))
    Table.insert(@project, @schema, row("table_untouched", %{"k" => "before"}))

    assert {1, _} =
             Table.update(@project, @schema, [data: %{"k" => "after"}], id: "table_update")

    assert Table.get_by(@project, @schema, @fields, id: "table_update").data == %{"k" => "after"}

    assert Table.get_by(@project, @schema, @fields, id: "table_untouched").data == %{
             "k" => "before"
           }
  end

  test "delete removes the row" do
    Table.insert(@project, @schema, row("table_delete"))
    assert Table.get_by(@project, @schema, @fields, id: "table_delete") != nil

    assert {:ok, nil} = Table.delete(@project, @schema, id: "table_delete")
    assert Table.get_by(@project, @schema, @fields, id: "table_delete") == nil
  end

  test "delete reports a row that is not there" do
    assert {:error, [%{context: "delete", message: "item not found"}]} =
             Table.delete(@project, @schema, id: "table_delete_absent")
  end
end

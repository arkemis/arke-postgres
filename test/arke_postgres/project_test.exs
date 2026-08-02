defmodule ArkePostgres.ProjectTest do
  @moduledoc """
  `create_project/1` and `delete_project/1` issue DDL, which the sandbox transaction
  cannot roll back, so these run unboxed and drop what they create.
  """

  use ArkePostgres.RepoCase

  @tag :unboxed
  test "create_project builds a schema with the arke tables" do
    id = "project_test_create"
    on_exit(fn -> ArkePostgres.delete_project(%{arke_id: :arke_project, id: id}) end)

    assert :ok = ArkePostgres.create_project(%{arke_id: :arke_project, id: id})

    assert schema_exists?(id)
    assert table_exists?(id, "arke_unit")
    assert table_exists?(id, "arke_link")
  end

  @tag :unboxed
  test "delete_project drops the schema" do
    id = "project_test_delete"
    ArkePostgres.create_project(%{arke_id: :arke_project, id: id})
    assert schema_exists?(id)

    ArkePostgres.delete_project(%{arke_id: :arke_project, id: id})

    refute schema_exists?(id)
  end

  @tag :unboxed
  test "create_project ignores a unit that is not an arke_project" do
    assert ArkePostgres.create_project(%{arke_id: :something_else, id: "nope"}) == nil
    refute schema_exists?("nope")
  end

  @tag :unboxed
  test "delete_project ignores a unit that is not an arke_project" do
    assert ArkePostgres.delete_project(%{arke_id: :something_else, id: "nope"}) == nil
  end

  test "get_project_record lists the seeded projects" do
    ids = ArkePostgres.Query.get_project_record() |> Enum.map(&to_string(&1.id)) |> Enum.sort()

    assert "arke_system" in ids
    assert "test_schema" in ids
  end

  test "init returns ok when the environment is set" do
    assert ArkePostgres.init() == :ok
  end
end

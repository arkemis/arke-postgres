defmodule ArkePostgres.PersistenceTest do
  use ArkePostgres.RepoCase

  setup do
    %{arke: create_arke(:persistence_test_arke, :persistence_label)}
  end

  describe "create/2" do
    test "persists a unit and returns it scoped to the project", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_create"))

      assert to_string(unit.id) == "persist_create"
      assert unit.metadata.project == @project
      assert QueryManager.get_by(id: :persist_create, project: @project) != nil
    end

    test "assigns an id when the unit has none", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, nil))

      assert is_binary(to_string(unit.id))
      assert to_string(unit.id) != ""
    end

    test "returns an error for a duplicate id", %{arke: arke} do
      {:ok, _} = ArkePostgres.create(@project, unit_for(arke, "persist_dup"))

      assert {:error, errors} = ArkePostgres.create(@project, unit_for(arke, "persist_dup"))
      refute Enum.empty?(errors)
    end
  end

  describe "update/2" do
    test "writes the new value", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_update"))

      {:ok, _} =
        ArkePostgres.update(@project, Arke.Core.Unit.update(unit, persistence_label: "after"))

      assert QueryManager.get_by(id: :persist_update, project: @project).data.persistence_label ==
               "after"
    end

    test "leaves other units alone", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_update_a"))
      {:ok, _} = ArkePostgres.create(@project, unit_for(arke, "persist_update_b", "before"))

      {:ok, _} =
        ArkePostgres.update(@project, Arke.Core.Unit.update(unit, persistence_label: "after"))

      assert QueryManager.get_by(id: :persist_update_b, project: @project).data.persistence_label ==
               "before"
    end
  end

  describe "update_key/2" do
    test "writes the keys that changed", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_key"))

      ArkePostgres.update_key(unit, Arke.Core.Unit.update(unit, persistence_label: "after"))

      assert QueryManager.get_by(id: :persist_key, project: @project).data.persistence_label ==
               "after"
    end

    test "leaves other units alone", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_key_a"))
      {:ok, _} = ArkePostgres.create(@project, unit_for(arke, "persist_key_b"))

      ArkePostgres.update_key(unit, Arke.Core.Unit.update(unit, persistence_label: "after"))

      assert QueryManager.get_by(id: :persist_key_b, project: @project).data.persistence_label ==
               "before"
    end
  end

  describe "delete/2" do
    test "removes the unit", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_delete"))

      assert {:ok, nil} = ArkePostgres.delete(@project, unit)
      assert QueryManager.get_by(id: :persist_delete, project: @project) == nil
    end

    test "leaves other units alone", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_delete_a"))
      {:ok, _} = ArkePostgres.create(@project, unit_for(arke, "persist_delete_b"))

      ArkePostgres.delete(@project, unit)

      assert QueryManager.get_by(id: :persist_delete_b, project: @project) != nil
    end
  end

  defp unit_for(arke, id, label \\ "before") do
    Arke.Core.Unit.load(arke, id: id, persistence_label: label)
  end
end

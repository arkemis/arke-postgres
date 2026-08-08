defmodule ArkePostgres.PersistenceTest do
  use ArkePostgres.RepoCase

  import Ecto.Query, only: [from: 2]

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

    test "leaves the project in the persisted metadata, unlike update/2", %{arke: arke} do
      # Pins current behaviour, not desired behaviour. `update_key/4` deletes the string key
      # "project" from a metadata map keyed by the atom `:project`, so the project survives the
      # write; `update/4` deletes the atom and strips it. See the update_key metadata spike.
      # The metadata is given explicitly: the arke's own metadata is global manager state that
      # another module's test can rewrite mid-suite, and this test is about the write paths.
      {:ok, updated} = ArkePostgres.create(@project, with_project(arke, "persist_md_update"))
      {:ok, keyed} = ArkePostgres.create(@project, with_project(arke, "persist_md_key"))

      ArkePostgres.update(@project, Arke.Core.Unit.update(updated, persistence_label: "after"))
      ArkePostgres.update_key(keyed, Arke.Core.Unit.update(keyed, persistence_label: "after"))

      assert persisted_metadata("persist_md_update") == %{}
      assert persisted_metadata("persist_md_key") == %{"project" => "test_schema"}
    end

    defp with_project(arke, id) do
      Arke.Core.Unit.load(arke,
        id: id,
        persistence_label: "before",
        metadata: %{project: :test_schema}
      )
    end

    defp persisted_metadata(id) do
      ArkePostgres.Repo.one(
        from(u in "arke_unit", where: u.id == ^id, select: u.metadata),
        prefix: to_string(@project)
      )
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

  describe "an arke that is neither an arke nor a table" do
    # `ArkeManager.get/2` answers nil for an unknown arke, which falls through every typed
    # clause of the write path.
    @unknown %{
      arke_id: :persistence_no_such_arke,
      id: "persist_unsupported",
      data: %{},
      metadata: %{project: :test_schema}
    }

    test "create says so, through the binary error passthrough" do
      assert ArkePostgres.create(@project, @unknown) == {:error, "arke type not supported"}
    end

    test "delete says so" do
      assert ArkePostgres.delete(@project, @unknown) == {:error, "arke type not supported"}
    end

    test "update says so" do
      assert ArkePostgres.handle_update(@project, nil, @unknown) ==
               {:error, "arke type not supported"}
    end

    test "update_key says so" do
      assert ArkePostgres.handle_update_key(nil, @unknown, @unknown) ==
               {:error, "arke type not supported"}
    end
  end

  describe "prefix isolation" do
    test "a write to test_schema does not land in arke_system", %{arke: arke} do
      {:ok, _} = ArkePostgres.create(@project, unit_for(arke, "persist_isolated"))

      assert ids_in("test_schema", "persist_isolated") == ["persist_isolated"]
      assert ids_in("arke_system", "persist_isolated") == []
    end

    test "a delete in test_schema does not reach arke_system", %{arke: arke} do
      {:ok, unit} = ArkePostgres.create(@project, unit_for(arke, "persist_isolated_delete"))
      {1, _} = seed_into("arke_system", "persist_isolated_delete")

      assert {:ok, nil} = ArkePostgres.delete(@project, unit)

      assert ids_in("test_schema", "persist_isolated_delete") == []
      assert ids_in("arke_system", "persist_isolated_delete") == ["persist_isolated_delete"]
    end

    defp ids_in(prefix, id) do
      ArkePostgres.Repo.all(from(u in "arke_unit", where: u.id == ^id, select: u.id),
        prefix: prefix
      )
    end

    defp seed_into(prefix, id) do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      ArkePostgres.Repo.insert_all(
        "arke_unit",
        [
          [
            id: id,
            arke_id: "persistence_test_arke",
            data: %{},
            metadata: %{},
            inserted_at: now,
            updated_at: now
          ]
        ],
        prefix: prefix
      )
    end
  end

  defp unit_for(arke, id, label \\ "before") do
    Arke.Core.Unit.load(arke, id: id, persistence_label: label)
  end
end

defmodule ArkePostgres.ArkeUnitTest do
  use ArkePostgres.RepoCase

  alias ArkePostgres.ArkeUnit

  setup do
    %{arke: create_arke(:arke_unit_test_arke, :arke_unit_label)}
  end

  describe "insert/3" do
    test "writes the row and returns it", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_insert", arke_unit_label: "hello")

      assert {:ok, record} = ArkeUnit.insert(@project, arke, unit)
      assert record.id == "arke_unit_insert"
      assert record.arke_id == "arke_unit_test_arke"
    end

    test "generates an id when the unit has none", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: nil, arke_unit_label: "hello")

      assert {:ok, record} = ArkeUnit.insert(@project, arke, unit)
      assert is_binary(record.id)
    end

    test "generates a lowercase, dash-separated v1 uuid when the unit has no id", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: nil, arke_unit_label: "hello")

      assert {:ok, record} = ArkeUnit.insert(@project, arke, unit)

      assert String.length(record.id) == 36

      assert record.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-1[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "generates a distinct id per insert", %{arke: arke} do
      ids =
        for _ <- 1..5 do
          unit = Arke.Core.Unit.load(arke, id: nil, arke_unit_label: "hello")
          {:ok, record} = ArkeUnit.insert(@project, arke, unit)
          record.id
        end

      assert length(Enum.uniq(ids)) == 5
    end

    test "takes an id that is already a string", %{arke: arke} do
      # `Unit.load/2` turns an id into an atom, so a binary one only reaches `insert/3` when
      # the unit was built by hand.
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_atom", arke_unit_label: "hello")

      assert {:ok, record} = ArkeUnit.insert(@project, arke, %{unit | id: "arke_unit_binary"})
      assert record.id == "arke_unit_binary"
    end

    test "returns changeset errors for a duplicate id", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_dup", arke_unit_label: "hello")
      {:ok, _} = ArkeUnit.insert(@project, arke, unit)

      assert {:error, errors} = ArkeUnit.insert(@project, arke, unit)
      refute Enum.empty?(errors)
    end
  end

  describe "update/4" do
    test "writes the new data", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_update", arke_unit_label: "before")
      {:ok, _} = ArkeUnit.insert(@project, arke, unit)

      updated =
        Arke.Core.Unit.update(unit,
          arke_unit_label: "after",
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )

      ArkeUnit.update(@project, arke, updated)

      assert QueryManager.get_by(id: :arke_unit_update, project: @project).data.arke_unit_label ==
               "after"
    end
  end

  describe "delete/3" do
    test "removes the row", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_delete", arke_unit_label: "x")
      {:ok, _} = ArkeUnit.insert(@project, arke, unit)

      assert {:ok, nil} = ArkeUnit.delete(@project, arke, unit)

      assert QueryManager.get_by(id: :arke_unit_delete, project: @project) == nil
    end

    test "reports a unit that is not there", %{arke: arke} do
      unit = Arke.Core.Unit.load(arke, id: "arke_unit_delete_absent", arke_unit_label: "x")

      assert {:error, [%{context: "delete", message: "item not found"}]} =
               ArkeUnit.delete(@project, arke, unit)
    end
  end

  describe "diff_keys/3" do
    test "returns only watched keys that changed" do
      assert ArkeUnit.diff_keys(%{label: "a"}, %{label: "b"}, [:label]) == [label: "b"]
    end

    test "ignores keys that are not watched" do
      assert ArkeUnit.diff_keys(%{label: "a"}, %{label: "b"}, [:other]) == []
    end

    test "treats a key missing from the old data as changed" do
      assert ArkeUnit.diff_keys(%{}, %{label: "a"}, [:label]) == [label: "a"]
    end

    test "returns nothing when nothing changed" do
      assert ArkeUnit.diff_keys(%{label: "a"}, %{label: "a"}, [:label]) == []
    end
  end

  describe "decode_unit_data/1" do
    test "unwraps the stored value envelope" do
      assert ArkeUnit.decode_unit_data(%{"label" => %{"value" => "hello"}}) == %{
               "label" => "hello"
             }
    end

    test "keeps a bare value as is" do
      assert ArkeUnit.decode_unit_data(%{"label" => "hello"}) == %{"label" => "hello"}
    end

    test "reads a missing value as nil" do
      assert ArkeUnit.decode_unit_data(%{"label" => %{"datetime" => "x"}}) == %{"label" => nil}
    end

    test "decodes every key" do
      stored = %{"a" => %{"value" => 1}, "b" => %{"value" => 2}}
      assert ArkeUnit.decode_unit_data(stored) == %{"a" => 1, "b" => 2}
    end
  end

  describe "encode_unit_data/2" do
    test "keeps a declared parameter", %{arke: arke} do
      assert Map.has_key?(
               ArkeUnit.encode_unit_data(arke, %{arke_unit_label: "hello"}),
               "arke_unit_label"
             )
    end

    test "drops an undeclared parameter", %{arke: arke} do
      refute Map.has_key?(ArkeUnit.encode_unit_data(arke, %{nope: "x"}), "nope")
    end

    test "encodes nothing from empty data", %{arke: arke} do
      assert ArkeUnit.encode_unit_data(arke, %{}) == %{}
    end

    test "drops a parameter marked only_runtime" do
      # `arke_file` links `binary_data` with `only_runtime: true`, so it must never be written.
      arke = ArkeManager.get(:arke_file, @project)

      encoded = ArkeUnit.encode_unit_data(arke, %{name: "n", binary_data: "raw bytes"})

      assert Map.keys(encoded) == ["name"]
    end
  end

  describe "format_arke_unit_record/1" do
    test "flattens the data column into the record" do
      record = [id: "x", arke_id: "y", data: %{"label" => %{"value" => "hello"}}]
      formatted = ArkeUnit.format_arke_unit_record(record)

      assert formatted[:id] == "x"
      assert formatted[:arke_id] == "y"
      assert formatted[:label] == "hello"
    end

    test "keeps columns other than data" do
      formatted = ArkeUnit.format_arke_unit_record(id: "x", metadata: %{"a" => 1}, data: %{})

      assert formatted[:metadata] == %{"a" => 1}
    end
  end
end

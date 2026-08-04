defmodule ArkePostgres.ManagerUnitsTest do
  @moduledoc """
  `get_manager_units/1` is what `ArkePostgres.init/0` feeds to the arke managers at boot. It
  runs on every start and nothing asserted its shape.

  `test_schema` is seeded from the shared registry, which contributes exactly one arke,
  `arke_file`, and its six parameters.
  """

  use ArkePostgres.RepoCase

  describe "get_manager_units/1" do
    setup do
      {parameters, arke_list, groups} = ArkePostgres.Query.get_manager_units(@project)
      %{parameters: parameters, arke_list: arke_list, groups: groups}
    end

    test "returns the seeded parameters with their type and project", %{parameters: parameters} do
      by_id = Map.new(parameters, &{&1.id, &1})

      assert Enum.sort(Map.keys(by_id)) ==
               ~w[binary_data extension name path provider size]

      assert by_id["size"].type == "float"
      assert by_id["name"].type == "string"
      assert by_id["name"].metadata == %{"project" => "test_schema"}
    end

    test "flattens each parameter's stored data onto the entry", %{parameters: parameters} do
      name = Enum.find(parameters, &(&1.id == "name"))

      assert name.label == "Name"
      assert name.persistence == "arke_parameter"
    end

    test "returns the seeded arke with the parameters linked to it", %{arke_list: arke_list} do
      assert [arke_file] = arke_list
      assert arke_file.id == "arke_file"
      assert arke_file.label == "Arke File"

      assert arke_file.parameters |> Enum.map(& &1.id) |> Enum.sort() ==
               ~w[binary_data extension name path provider size]a
    end

    test "carries the link metadata onto each of an arke's parameters", %{arke_list: arke_list} do
      [arke_file] = arke_list
      binary_data = Enum.find(arke_file.parameters, &(&1.id == :binary_data))

      assert binary_data.metadata.only_runtime == true
      assert binary_data.metadata.required == true
    end

    test "returns no groups when none are seeded", %{groups: groups} do
      assert groups == []
    end
  end

  describe "parse_groups/2 through get_manager_units/1" do
    setup do
      {:ok, _} =
        QueryManager.create(@project, ArkeManager.get(:arke, :arke_system), %{
          id: "mu_linked_arke",
          label: "Linked arke"
        })

      # `arke_list` creates the group links, so `mu_linked_arke` gets one and the name that
      # matches no unit does not.
      {:ok, _} =
        QueryManager.create(@project, ArkeManager.get(:group, :arke_system), %{
          id: "mu_group",
          label: "Group under test",
          arke_list: ["mu_linked_arke", "mu_unlinked_arke"]
        })

      {_parameters, _arke_list, groups} = ArkePostgres.Query.get_manager_units(@project)
      %{group: Enum.find(groups, &(&1.id == "mu_group"))}
    end

    test "resolves a linked arke into an entry carrying the link metadata", %{group: group} do
      assert %{id: :mu_linked_arke, metadata: metadata} =
               Enum.find(group.arke_list, &is_map(&1))

      assert metadata["parameter_id"] == "arke_list"
    end

    test "keeps a name with no link row as the raw key", %{group: group} do
      assert "mu_unlinked_arke" in group.arke_list
    end

    test "flattens the group's own data onto the entry", %{group: group} do
      assert group.label == "Group under test"
    end
  end

  describe "merge_unit_metadata/3" do
    test "the unit's metadata wins over the link's" do
      params = [%{child_id: "p", metadata: %{"kept" => 1, "overridden" => 1}}]

      assert ArkePostgres.Query.merge_unit_metadata(
               params,
               %{"p" => %{"overridden" => 2}},
               @project
             ) ==
               [%{child_id: "p", metadata: %{"kept" => 1, "overridden" => 2}}]
    end

    test "a link with no matching unit keeps its own metadata" do
      params = [%{child_id: "absent", metadata: %{"kept" => 1}}]

      assert ArkePostgres.Query.merge_unit_metadata(params, %{}, @project) ==
               [%{child_id: "absent", metadata: %{"kept" => 1}}]
    end

    test "an arke_system project is stripped for another project" do
      params = [%{child_id: "p", metadata: %{}}]

      assert ArkePostgres.Query.merge_unit_metadata(
               params,
               %{"p" => %{"project" => "arke_system"}},
               @project
             ) == [%{child_id: "p", metadata: %{}}]
    end

    test "an arke_system project is kept for arke_system itself" do
      params = [%{child_id: "p", metadata: %{}}]

      assert ArkePostgres.Query.merge_unit_metadata(
               params,
               %{"p" => %{"project" => "arke_system"}},
               :arke_system
             ) == [%{child_id: "p", metadata: %{"project" => "arke_system"}}]
    end
  end
end

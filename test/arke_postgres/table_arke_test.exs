defmodule ArkePostgres.TableArkeTest do
  @moduledoc """
  The `type: "table"` branch of the write path, driven through the `ArkePostgres` boundary.

  `arke_link` is the only table-type arke in use, so links are what these write. The data to
  set and the `WHERE` clause both come out of `filter_primary_keys/2`: primary parameters
  build the where, the rest build the update.
  """

  use ArkePostgres.RepoCase

  import Ecto.Query, only: [from: 2]

  setup do
    arke = create_arke(:ta_arke, :ta_label)

    for id <- ~w[ta_p ta_c ta_other] do
      {:ok, _} = QueryManager.create(@project, arke, %{id: id, ta_label: id})
    end

    %{arke_link: ArkeManager.get(:arke_link, @project)}
  end

  defp add_link(parent, child, type),
    do: {:ok, _} = LinkManager.add_node(@project, parent, child, type, %{})

  defp link_unit(arke_link, parent, child) do
    QueryManager.query(project: @project, arke: arke_link)
    |> QueryManager.filter(:parent_id, :eq, parent, false)
    |> QueryManager.filter(:child_id, :eq, child, false)
    |> QueryManager.one()
  end

  defp ta_links do
    ArkePostgres.Repo.all(
      from(l in "arke_link", where: l.parent_id == "ta_p", select: [:parent_id, :child_id, :type]),
      prefix: to_string(@project)
    )
    |> Enum.sort_by(&{&1.child_id, &1.type})
  end

  describe "handle_update/3" do
    test "writes the non-primary columns of the link", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_before")
      link = link_unit(arke_link, "ta_p", "ta_c")

      assert {:ok, _} =
               ArkePostgres.handle_update(
                 @project,
                 arke_link,
                 Arke.Core.Unit.update(link, type: "ta_after")
               )

      assert ta_links() == [%{parent_id: "ta_p", child_id: "ta_c", type: "ta_after"}]
    end

    test "leaves a link to a different child alone", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_before")
      add_link("ta_p", "ta_other", "ta_before")

      link = link_unit(arke_link, "ta_p", "ta_c")

      ArkePostgres.handle_update(
        @project,
        arke_link,
        Arke.Core.Unit.update(link, type: "ta_after")
      )

      assert ta_links() == [
               %{parent_id: "ta_p", child_id: "ta_c", type: "ta_after"},
               %{parent_id: "ta_p", child_id: "ta_other", type: "ta_before"}
             ]
    end
  end

  describe "handle_update_key/3" do
    test "writes through the same where clause", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_before")
      add_link("ta_p", "ta_other", "ta_before")

      link = link_unit(arke_link, "ta_p", "ta_c")

      assert {:ok, _} =
               ArkePostgres.handle_update_key(
                 arke_link,
                 link,
                 Arke.Core.Unit.update(link, type: "ta_after")
               )

      assert ta_links() == [
               %{parent_id: "ta_p", child_id: "ta_c", type: "ta_after"},
               %{parent_id: "ta_p", child_id: "ta_other", type: "ta_before"}
             ]
    end
  end

  describe "delete/2" do
    test "removes only the matching link", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_type")
      add_link("ta_p", "ta_other", "ta_type")

      link = link_unit(arke_link, "ta_p", "ta_c")

      assert {:ok, nil} = ArkePostgres.delete(@project, link)

      assert ta_links() == [%{parent_id: "ta_p", child_id: "ta_other", type: "ta_type"}]
    end

    test "reports a link that is not there", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_type")
      link = link_unit(arke_link, "ta_p", "ta_c")
      absent = Arke.Core.Unit.update(link, child_id: "ta_absent")

      assert {:error, [%{context: "delete", message: "item not found"}]} =
               ArkePostgres.delete(@project, absent)

      assert ta_links() == [%{parent_id: "ta_p", child_id: "ta_c", type: "ta_type"}]
    end
  end

  describe "filter_primary_keys/2" do
    test "the where clause ignores type, so both links of a pair are rewritten", %{
      arke_link: arke_link
    } do
      # `type` is not a primary parameter of `arke_link`, so it never reaches the where clause,
      # even though the table's primary key includes it. Two links between the same pair
      # therefore cannot be updated independently.
      add_link("ta_p", "ta_c", "ta_one")
      add_link("ta_p", "ta_c", "ta_two")

      assert_raise Postgrex.Error, fn ->
        ArkePostgres.handle_update(@project, arke_link, of_pair(arke_link, "ta_three"))
      end
    end

    test "deleting one of a pair's links deletes both", %{arke_link: arke_link} do
      add_link("ta_p", "ta_c", "ta_one")
      add_link("ta_p", "ta_c", "ta_two")

      assert {:ok, nil} = ArkePostgres.delete(@project, of_pair(arke_link, "ta_one"))
      assert ta_links() == []
    end

    # A pair with two links cannot be fetched with `one/1`, so build the unit by hand.
    defp of_pair(arke_link, type) do
      Arke.Core.Unit.load(arke_link,
        parent_id: "ta_p",
        child_id: "ta_c",
        type: type,
        metadata: %{project: @project}
      )
    end
  end
end

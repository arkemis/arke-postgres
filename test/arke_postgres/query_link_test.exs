defmodule ArkePostgres.QueryLinkTest do
  @moduledoc """
  Link traversal through the recursive CTE, beyond the single hop `query_test.exs` covers.

  The chain is `ql_a -> ql_b -> ql_c` on type `ql_type`, plus `ql_a -> ql_d` on `ql_other`
  so the type filter has something to exclude.
  """

  use ArkePostgres.RepoCase

  setup do
    arke = create_arke(:ql_arke, :ql_label)

    for id <- ~w[ql_a ql_b ql_c ql_d] do
      {:ok, _} = QueryManager.create(@project, arke, %{id: id, ql_label: id})
    end

    {:ok, _} = LinkManager.add_node(@project, "ql_a", "ql_b", "ql_type", %{"hop" => 1})
    {:ok, _} = LinkManager.add_node(@project, "ql_b", "ql_c", "ql_type", %{"hop" => 2})
    {:ok, _} = LinkManager.add_node(@project, "ql_a", "ql_d", "ql_other", %{})

    :ok
  end

  defp linked(unit, opts, action \\ :all) do
    QueryManager.query(project: @project)
    |> QueryManager.link(unit, opts)
    |> then(&ArkePostgres.Query.execute(&1, action))
  end

  defp from_a(opts, action \\ :all), do: linked(%{id: :ql_a}, opts, action)

  describe "depth" do
    # The CTE recurses while `depth < ^depth`, and the direct links are already depth 0, so
    # `depth: n` walks n + 1 hops. `depth: 0` is the single hop.
    test "depth 0 stops at the direct child" do
      assert ids(from_a(depth: 0, direction: :child, type: "ql_type")) == ["ql_b"]
    end

    test "depth 1 follows the recursive arm one hop further" do
      assert ids(from_a(depth: 1, direction: :child, type: "ql_type")) == ["ql_b", "ql_c"]
    end

    test "a depth past the end of the chain adds nothing" do
      assert ids(from_a(depth: 9, direction: :child, type: "ql_type")) == ["ql_b", "ql_c"]
    end

    test "depth 0 backwards stops at the direct parent" do
      units = linked(%{id: :ql_c}, depth: 0, direction: :parent, type: "ql_type")

      assert ids(units) == ["ql_b"]
    end

    test "depth 1 backwards reaches both ancestors" do
      units = linked(%{id: :ql_c}, depth: 1, direction: :parent, type: "ql_type")

      assert ids(units) == ["ql_a", "ql_b"]
    end

    test "count follows the same depth" do
      assert from_a([depth: 1, direction: :child, type: "ql_type"], :count) == 2
      assert from_a([depth: 0, direction: :child, type: "ql_type"], :count) == 1
    end
  end

  describe "type" do
    test "a type keeps only links of that type" do
      assert ids(from_a(depth: 0, direction: :child, type: "ql_type")) == ["ql_b"]
    end

    test "no type keeps links of every type" do
      assert ids(from_a(depth: 0, direction: :child, type: nil)) == ["ql_b", "ql_d"]
    end
  end

  describe "a list of starting units" do
    test "returns each reachable unit once per starting unit" do
      units = linked([%{id: :ql_a}, %{id: :ql_b}], depth: 1, direction: :child, type: "ql_type")

      assert ids(units) == ["ql_b", "ql_c", "ql_c"]

      assert units |> Enum.map(& &1.link.starting_unit) |> Enum.sort() ==
               ["ql_a", "ql_a", "ql_b"]
    end
  end

  describe "the link columns on the returned unit" do
    test "depth, metadata and starting unit survive into unit.link" do
      units = from_a(depth: 1, direction: :child, type: "ql_type")
      by_id = Map.new(units, &{to_string(&1.id), &1})

      assert by_id["ql_b"].link == %{depth: 0, metadata: %{"hop" => 1}, starting_unit: "ql_a"}
      assert by_id["ql_c"].link == %{depth: 1, metadata: %{"hop" => 2}, starting_unit: "ql_a"}
    end

    test "link_type is selected by the query but dropped by the unit" do
      # `Arke.Core.Unit` builds `link` from depth, link_metadata and starting_unit only, so the
      # type of the link that was walked is not recoverable from the result.
      [unit | _] = from_a(depth: 0, direction: :child, type: "ql_type")

      refute Map.has_key?(unit.link, :type)
      refute Map.has_key?(unit.data, :link_type)
    end

    test "the unit still carries its own parameters" do
      [unit] = from_a(depth: 0, direction: :child, type: "ql_type")

      assert unit.data.ql_label == "ql_b"
      assert unit.metadata.project == @project
    end
  end
end

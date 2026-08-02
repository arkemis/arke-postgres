defmodule ArkePostgres.QueryTest do
  @moduledoc """
  Unit tests for query generation.

  `execute(query, :pseudo_query)` returns the Ecto query without running it, so these
  assert on generated SQL and its bound parameters rather than on rows. Assertions match
  SQL fragments, not whole statements, so they survive Ecto formatting changes.
  """

  use ArkePostgres.RepoCase

  alias Arke.Boundary.ParameterManager

  defp base, do: QueryManager.query(project: :test_schema, arke: ArkeManager.get(:arke, :arke_system))

  defp param(id), do: ParameterManager.get(id, :arke_system)

  defp filter(parameter_id, operator, value, negate \\ false) do
    condition = QueryManager.condition(param(parameter_id), operator, value, negate)

    QueryManager.and_(base(), false, [condition])
    |> ArkePostgres.Query.execute(:pseudo_query)
    |> then(&Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, &1))
  end

  describe "column casting per parameter type" do
    test "string compares as text" do
      {sql, params} = filter(:label, :eq, "hello")

      assert sql =~ "::text"
      assert params == ["label", "hello"]
    end

    test "integer compares as integer" do
      {sql, params} = filter(:default_integer, :gt, 5)

      assert sql =~ "::integer"
      assert params == ["default_integer", 5]
    end

    test "float compares as float" do
      {sql, params} = filter(:default_float, :lte, 2.5)

      assert sql =~ "::float"
      assert params == ["default_float", 2.5]
    end

    test "boolean compares as boolean" do
      {sql, params} = filter(:default_boolean, :eq, true)

      assert sql =~ "::boolean"
      assert params == ["default_boolean", true]
    end
  end

  describe "operators" do
    test "eq" do
      {sql, _} = filter(:label, :eq, "hello")
      assert sql =~ ~r/=\s*\$2/
    end

    test "gt, gte, lt and lte emit their comparison" do
      for {operator, fragment} <- [gt: ">", gte: ">=", lt: "<", lte: "<="] do
        {sql, _} = filter(:default_integer, operator, 5)
        assert sql =~ "#{fragment} $2", "expected #{operator} to emit #{fragment}"
      end
    end

    test "contains, startswith and endswith use LIKE" do
      for operator <- [:contains, :startswith, :endswith] do
        {sql, params} = filter(:label, operator, "abc")
        assert sql =~ "LIKE", "expected #{operator} to use LIKE"
        assert ["label", pattern] = params
        assert pattern =~ "abc"
      end
    end

    test "icontains is case insensitive" do
      {sql, _} = filter(:label, :icontains, "abc")
      assert sql =~ "ILIKE"
    end

    test "isnull checks for null" do
      {sql, _} = filter(:label, :isnull, nil)
      assert sql =~ "IS NULL"
    end

    test "negate wraps the condition in NOT" do
      {sql, _} = filter(:default_integer, :gt, 5, true)
      assert sql =~ "NOT"
    end
  end

  describe "in operator" do
    test "binds a list against ANY" do
      {sql, params} = filter(:default_integer, :in, [3, 10])

      assert sql =~ "ANY($2)"
      assert params == ["default_integer", [3, 10]]
    end

    test "casts list values to the parameter type" do
      {_sql, params} = filter(:default_integer, :in, ["3", "10"])

      assert params == ["default_integer", [3, 10]]
    end

    test "casts list values for float parameters" do
      {_sql, params} = filter(:default_float, :in, ["3", "10.5"])

      assert params == ["default_float", [3.0, 10.5]]
    end
  end

  describe "pagination and ordering" do
    defp paginated(fun) do
      base()
      |> fun.()
      |> ArkePostgres.Query.execute(:pseudo_query)
      |> then(&Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, &1))
    end

    test "limit and offset" do
      {sql, _} = paginated(&(QueryManager.limit(&1, 10) |> QueryManager.offset(5)))

      assert sql =~ "LIMIT"
      assert sql =~ "OFFSET"
    end

    test "order emits a direction" do
      {sql, _} = paginated(&QueryManager.order(&1, param(:label), :desc))

      assert sql =~ "ORDER BY"
      assert sql =~ "DESC"
    end
  end

  describe "execute/2" do
    setup do
      arke = create_arke(:query_exec_arke, :query_exec_label)
      create_unit(arke, "query_exec_a", %{query_exec_label: "alpha"})
      create_unit(arke, "query_exec_b", %{query_exec_label: "beta"})
      %{arke: arke}
    end

    test "all returns every unit of the arke", %{arke: arke} do
      units = QueryManager.query(project: @project, arke: arke) |> QueryManager.all()

      assert ids(units) == ["query_exec_a", "query_exec_b"]
    end

    test "count matches the number of units", %{arke: arke} do
      assert QueryManager.query(project: @project, arke: arke) |> QueryManager.count() == 2
    end

    test "one returns a single unit", %{arke: arke} do
      unit =
        QueryManager.query(project: @project, arke: arke)
        |> QueryManager.where(id: "query_exec_a")
        |> QueryManager.one()

      assert to_string(unit.id) == "query_exec_a"
    end

    test "one returns nil when nothing matches", %{arke: arke} do
      unit =
        QueryManager.query(project: @project, arke: arke)
        |> QueryManager.where(id: "query_exec_absent")
        |> QueryManager.one()

      assert unit == nil
    end
  end

  describe "get_column/2" do
    test "reads an arke parameter out of the data blob" do
      column = ArkePostgres.Query.get_column(param(:label))

      assert inspect(column) =~ "data"
    end

    test "reads a table column directly" do
      column = ArkePostgres.Query.get_column(param(:id))

      refute inspect(column) =~ "->"
    end
  end

  describe "extract_path/1" do
    test "returns the path of a base filter" do
      condition = QueryManager.condition(param(:label), :eq, "x", false)

      assert ArkePostgres.Query.extract_path(condition) == [[]]
    end

    test "returns nothing for anything else" do
      assert ArkePostgres.Query.extract_path(:not_a_filter) == []
    end
  end

  describe "remove_arke_system/2" do
    test "keeps metadata untouched for arke_system" do
      metadata = %{"project" => "arke_system"}

      assert ArkePostgres.Query.remove_arke_system(metadata, :arke_system) == metadata
    end

    test "strips the project when it points at arke_system" do
      assert ArkePostgres.Query.remove_arke_system(%{"project" => "arke_system"}, :test_schema) ==
               %{}
    end

    test "keeps a project that is not arke_system" do
      metadata = %{"project" => "test_schema"}

      assert ArkePostgres.Query.remove_arke_system(metadata, :test_schema) == metadata
    end
  end

  describe "init_unit/3" do
    test "returns nil for a missing record" do
      assert ArkePostgres.Query.init_unit(nil, nil, @project) == nil
    end
  end
end

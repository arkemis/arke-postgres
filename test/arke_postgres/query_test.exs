defmodule ArkePostgres.QueryTest do
  @moduledoc """
  Unit tests for query generation.

  `execute(query, :pseudo_query)` returns the Ecto query without running it, so these
  assert on generated SQL and its bound parameters rather than on rows. Assertions match
  SQL fragments, not whole statements, so they survive Ecto formatting changes.
  """

  use ArkePostgres.RepoCase

  alias Arke.Boundary.ParameterManager

  defp base,
    do: QueryManager.query(project: :test_schema, arke: ArkeManager.get(:arke, :arke_system))

  defp param(id), do: ParameterManager.get(id, :arke_system)

  defp filter(parameter_id, operator, value, negate \\ false) do
    condition = QueryManager.condition(param(parameter_id), operator, value, negate)

    QueryManager.and_(base(), false, [condition])
    |> ArkePostgres.Query.execute(:pseudo_query)
    |> then(&Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, &1))
  end

  # `QueryManager.condition/4` casts the value itself, and raises on its own before the adapter
  # ever sees it. Building the filter structs by hand is the only way to reach the adapter's
  # coercion and its error paths.
  defp raw_filter(parameter, operator, value) do
    base_filter = %Arke.Core.Query.BaseFilter{
      parameter: parameter,
      operator: operator,
      value: value,
      negate: false,
      path: []
    }

    filter = %Arke.Core.Query.Filter{logic: :and, negate: false, base_filters: [base_filter]}

    QueryManager.filter(base(), filter)
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

    for {parameter_id, value, cast} <- [
          {:default_datetime, "2026-01-02T03:04:05Z", "::timestamp"},
          {:default_date, "2026-01-02", "::date"},
          {:default_time, "03:04:05", "::time"},
          {:default_dict, %{"a" => 1}, "::JSON"},
          {:default_list, ["a"], "::JSON"},
          {:default_link, "x", "::text"},
          {:default_dynamic, "x", "::text"},
          {:filter_keys, "x", "::jsonb"}
        ] do
      test "#{parameter_id} compares as #{cast}" do
        {sql, _} = filter(unquote(parameter_id), :eq, unquote(Macro.escape(value)))

        assert sql =~ unquote(cast)
      end
    end

    test "atom casts to text, though no seeded parameter has that type" do
      parameter = %{id: :an_atom, arke_id: :atom, data: %{persistence: "arke_parameter"}}

      assert inspect(ArkePostgres.Query.get_column(parameter, nil)) =~ "::text"
    end
  end

  describe "get_value/2 coercion" do
    for {value, expected} <- [
          {true, true},
          {"true", true},
          {"True", true},
          {1, true},
          {"1", true},
          {false, false},
          {"false", false},
          {"False", false},
          {0, false},
          {"0", false}
        ] do
      test "boolean reads #{inspect(value)} as #{expected}" do
        {_sql, params} = raw_filter(param(:default_boolean), :eq, unquote(value))

        assert params == ["default_boolean", unquote(expected)]
      end
    end

    test "datetime parses a string" do
      {_sql, params} = raw_filter(param(:default_datetime), :eq, "2026-01-02T03:04:05Z")

      assert params == ["default_datetime", ~U[2026-01-02 03:04:05Z]]
    end

    test "date parses a string" do
      {_sql, params} = raw_filter(param(:default_date), :eq, "2026-01-02")

      assert params == ["default_date", ~D[2026-01-02]]
    end

    test "time parses a string" do
      {_sql, params} = raw_filter(param(:default_time), :eq, "03:04:05")

      assert params == ["default_time", ~T[03:04:05]]
    end

    for parameter_id <- [:default_dict, :default_list, :default_link, :default_dynamic] do
      test "#{parameter_id} passes its value through untouched" do
        {_sql, params} = raw_filter(param(unquote(parameter_id)), :eq, "as is")

        assert params == [to_string(unquote(parameter_id)), "as is"]
      end
    end

    test "an atom value becomes its string" do
      {_sql, params} = raw_filter(param(:label), :eq, :hello)

      assert params == ["label", "hello"]
    end

    test "a non-binary value for a string parameter is inspected" do
      {_sql, params} = raw_filter(param(:label), :eq, 5)

      assert params == ["label", "5"]
    end

    test "integer parses a string" do
      {_sql, params} = raw_filter(param(:default_integer), :eq, "42")

      assert params == ["default_integer", 42]
    end

    test "float parses a string" do
      {_sql, params} = raw_filter(param(:default_float), :eq, "4.5")

      assert params == ["default_float", 4.5]
    end
  end

  describe "get_value/2 rejections" do
    for {parameter_id, value} <- [
          {:default_integer, "not a number"},
          {:default_float, "not a number"},
          {:default_boolean, "maybe"},
          {:default_datetime, "not a datetime"},
          {:default_date, "not a date"},
          {:default_time, "not a time"}
        ] do
      test "#{parameter_id} rejects #{inspect(value)}" do
        assert_raise RuntimeError, "Parameter(#{unquote(parameter_id)}) value not valid", fn ->
          raw_filter(param(unquote(parameter_id)), :eq, unquote(value))
        end
      end
    end

    test "a list is passed through whatever it holds" do
      # `get_value/2` matches `is_list` before it ever reaches a parameter type, so
      # `parse_number_list/3` and its mixed-type rejection cannot be reached from here. Arke
      # casts list values on the way in, which is why `in` filters still work.
      {_sql, params} = raw_filter(param(:default_integer), :in, [1, "2"])

      assert params == ["default_integer", [1, "2"]]
    end

    test "a parameter type with no coercion clause is rejected" do
      parameter = %{id: :an_atom, arke_id: :atom, data: %{persistence: "arke_parameter"}}

      assert_raise RuntimeError, "Parameter(an_atom) value not valid", fn ->
        raw_filter(parameter, :eq, 5)
      end
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

    test "icontains, istartswith and iendswith are case insensitive" do
      for operator <- [:icontains, :istartswith, :iendswith] do
        {sql, _} = filter(:label, operator, "abc")
        assert sql =~ "ILIKE", "expected #{operator} to use ILIKE"
      end
    end

    test "isnull checks for null" do
      {sql, _} = filter(:label, :isnull, nil)
      assert sql =~ "IS NULL"
    end

    test "a negated isnull drops the key check" do
      {sql, _} = filter(:label, :isnull, nil, true)

      assert sql =~ "IS NULL"
      refute sql =~ "data ?"
    end

    test "negate wraps the condition in NOT" do
      {sql, _} = filter(:default_integer, :gt, 5, true)
      assert sql =~ "NOT"
    end

    test "a multiple parameter asks whether the value is one of its keys" do
      {sql, params} = filter(:filter_keys, :eq, "abc")

      assert sql =~ "jsonb_exists"
      assert params == ["filter_keys", "abc"]
    end

    test "an unknown operator falls back to equality" do
      {sql, _} = filter(:label, :no_such_operator, "abc")

      assert sql =~ ~r/=\s*\$2/
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

    test "raw returns the statement and its bindings instead of rows", %{arke: arke} do
      {sql, params} = QueryManager.query(project: @project, arke: arke) |> QueryManager.raw()

      assert sql =~ "SELECT"
      assert sql =~ "FROM \"arke_unit\""
      assert params == ["query_exec_arke"]
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
    setup do
      %{arke: create_arke(:query_init_arke, :query_init_label)}
    end

    defp record(data),
      do: %{
        id: "query_init_a",
        arke_id: "query_init_arke",
        data: data,
        metadata: %{"tenant" => "acme"},
        inserted_at: nil,
        updated_at: nil
      }

    defp stored(value), do: %{"value" => value, "datetime" => "2026-01-02T03:04:05Z"}

    test "returns nil for a missing record" do
      assert ArkePostgres.Query.init_unit(nil, nil, @project) == nil
    end

    test "projects the parameters the arke declares", %{arke: arke} do
      unit =
        ArkePostgres.Query.init_unit(
          record(%{"query_init_label" => stored("alpha")}),
          arke,
          @project
        )

      assert to_string(unit.id) == "query_init_a"
      assert unit.data.query_init_label == "alpha"
    end

    test "reads a parameter the record does not hold as nil", %{arke: arke} do
      unit = ArkePostgres.Query.init_unit(record(%{}), arke, @project)

      assert unit.data.query_init_label == nil
    end

    test "drops a column the arke does not declare", %{arke: arke} do
      data = %{"query_init_label" => stored("alpha"), "not_a_parameter" => stored("x")}

      unit = ArkePostgres.Query.init_unit(record(data), arke, @project)

      refute Map.has_key?(unit.data, :not_a_parameter)
      refute Map.has_key?(unit.data, "not_a_parameter")
    end

    test "injects the project into the metadata", %{arke: arke} do
      unit = ArkePostgres.Query.init_unit(record(%{}), arke, @project)

      assert unit.metadata.project == @project
      assert unit.metadata["tenant"] == "acme"
    end

    test "resolves the arke from the record when none is given" do
      unit =
        ArkePostgres.Query.init_unit(record(%{"query_init_label" => stored("a")}), nil, @project)

      assert unit.arke_id == :query_init_arke
      assert unit.data.query_init_label == "a"
    end
  end

  describe "link queries over the recursive cte" do
    setup do
      arke = create_arke(:query_link_arke, :query_link_label)

      for id <- ~w[query_link_parent query_link_child query_link_other] do
        {:ok, _} = QueryManager.create(@project, arke, %{id: id, query_link_label: id})
      end

      {:ok, _} =
        LinkManager.add_node(
          @project,
          "query_link_parent",
          "query_link_child",
          "query_link_type"
        )

      %{arke: arke}
    end

    defp linked(action, direction) do
      QueryManager.query(project: @project)
      |> QueryManager.link(%{id: :query_link_parent},
        depth: 1,
        direction: direction,
        type: "query_link_type"
      )
      |> then(&ArkePostgres.Query.execute(&1, action))
    end

    test "returns the linked child and nothing else" do
      ids = linked(:all, :child) |> Enum.map(&to_string(&1.id))

      assert ids == ["query_link_child"]
    end

    test "counts only the linked child" do
      assert linked(:count, :child) == 1
    end

    test "walks the link backwards from the child" do
      ids =
        QueryManager.query(project: @project)
        |> QueryManager.link(%{id: :query_link_child},
          depth: 1,
          direction: :parent,
          type: "query_link_type"
        )
        |> then(&ArkePostgres.Query.execute(&1, :all))
        |> Enum.map(&to_string(&1.id))

      assert ids == ["query_link_parent"]
    end
  end
end

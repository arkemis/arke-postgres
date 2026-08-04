defmodule ArkePostgres.QueryPathTest do
  @moduledoc """
  Filters and orders that carry a path, and the boolean composition of clauses.

  A path turns into a `LEFT JOIN` on `arke_unit`, aliased by the first parameter of the path
  and joined on that parameter's stored value matching the joined row's id. The filtered
  parameter is then read from the joined row rather than from the base row.

  Assertions match SQL fragments, not whole statements, so they survive Ecto formatting
  changes. Ecto names the base row `a0` and the first join `a1`.
  """

  use ArkePostgres.RepoCase

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Arke.Boundary.ParameterManager
  alias Arke.Core.Query, as: CoreQuery

  defp param(id), do: ParameterManager.get(id, :arke_system)

  defp base, do: QueryManager.query(project: @project, arke: ArkeManager.get(:arke, :arke_system))

  defp to_sql(query) do
    ArkePostgres.Query.execute(query, :pseudo_query)
    |> then(&Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, &1))
  end

  defp grouped(logic, negate, conditions) do
    apply(QueryManager, logic, [base(), negate, conditions])
    |> to_sql()
  end

  # `:parameters` is a link parameter on the arke model, so it holds the id of another unit
  # and is a valid thing to join on.
  defp path, do: [param(:parameters)]

  describe "a filter path builds a join" do
    test "joins arke_unit on the path parameter" do
      {sql, params} =
        grouped(:and_, false, [QueryManager.condition(param(:label), :eq, "x", false, path())])

      assert sql =~ "LEFT OUTER JOIN \"arke_unit\" AS a1"
      assert sql =~ ~r/ON \(a0\."data" -> \$1 ->> 'value'\)/
      assert params == ["parameters", "label", "x"]
    end

    test "the filtered parameter reads from the joined row" do
      {sql, _} =
        grouped(:and_, false, [QueryManager.condition(param(:label), :eq, "x", false, path())])

      assert sql =~ ~r/WHERE \(\(a1\."data" -> \$2 ->> 'value'\)::text = \$3\)/
    end

    test "two filters on the same path share one join" do
      {sql, _} =
        grouped(:and_, false, [
          QueryManager.condition(param(:label), :eq, "x", false, path()),
          QueryManager.condition(param(:format), :eq, "y", false, path())
        ])

      assert sql =~ " AND "
      assert length(String.split(sql, "LEFT OUTER JOIN")) == 2
    end

    test "isnull through a path checks the joined row" do
      {sql, _} =
        grouped(:and_, false, [QueryManager.condition(param(:label), :isnull, nil, false, path())])

      assert sql =~ "IS NULL"
      assert sql =~ "a1.data ?"
    end

    test "an order path builds the join and orders by the joined row" do
      {sql, _} = base() |> QueryManager.order([:parameters, :label], :asc) |> to_sql()

      assert sql =~ "LEFT OUTER JOIN \"arke_unit\" AS a1"
      assert sql =~ ~r/ORDER BY \(a1\."data" -> \$2 ->> 'value'\)::text/
    end
  end

  describe "column casts through a join alias" do
    # {parameter type, multiple, expected postgres cast}
    @casts [
      {:string, true, "::jsonb"},
      {:atom, false, "::text"},
      {:string, false, "::text"},
      {:link, false, "::text"},
      {:dynamic, false, "::text"},
      {:boolean, false, "::boolean"},
      {:integer, false, "::integer"},
      {:float, false, "::float"},
      {:datetime, false, "::timestamp"},
      {:date, false, "::date"},
      {:time, false, "::time"},
      {:dict, false, "::JSON"},
      {:list, false, "::JSON"}
    ]

    for {type, multiple, cast} <- @casts do
      test "#{type}#{if multiple, do: " multiple"} casts to #{cast}" do
        parameter = %{
          id: :joined_column,
          arke_id: unquote(type),
          data: %{persistence: "arke_parameter", multiple: unquote(multiple)}
        }

        sql = joined_column_sql(parameter)

        assert sql =~ unquote(cast)
        assert sql =~ "a1.\"data\""
      end
    end

    # `get_column/2` returns a dynamic bound to a named join, which cannot be rendered on its
    # own. Wrap it in the smallest query that carries a join by that name.
    defp joined_column_sql(parameter) do
      value = "x"
      condition = dynamic([q], ^ArkePostgres.Query.get_column(parameter, :joined) == ^value)

      from(u in "arke_unit",
        left_join: j in "arke_unit",
        as: :joined,
        on: true,
        where: ^condition,
        select: u.id
      )
      |> then(&Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, &1))
      |> elem(0)
    end
  end

  describe "filters across a link, executed" do
    setup do
      target = create_arke(:qp_target, :qp_target_label)
      source = create_arke(:qp_source, :qp_ref)

      create_unit(target, "qp_target_a", %{qp_target_label: "alpha"})
      create_unit(target, "qp_target_b", %{qp_target_label: "beta"})
      create_unit(source, "qp_source_a", %{qp_ref: "qp_target_a"})
      create_unit(source, "qp_source_b", %{qp_ref: "qp_target_b"})

      %{source: source}
    end

    test "returns only the units whose linked unit matches", %{source: source} do
      condition =
        QueryManager.condition(
          ParameterManager.get(:qp_target_label, @project),
          :eq,
          "alpha",
          false,
          [ParameterManager.get(:qp_ref, @project)]
        )

      units =
        QueryManager.query(project: @project, arke: source)
        |> QueryManager.and_(false, [condition])
        |> QueryManager.all()

      assert ids(units) == ["qp_source_a"]
    end

    test "returns nothing when no linked unit matches", %{source: source} do
      condition =
        QueryManager.condition(
          ParameterManager.get(:qp_target_label, @project),
          :eq,
          "gamma",
          false,
          [ParameterManager.get(:qp_ref, @project)]
        )

      units =
        QueryManager.query(project: @project, arke: source)
        |> QueryManager.and_(false, [condition])
        |> QueryManager.all()

      assert units == []
    end
  end

  describe "boolean composition" do
    defp conditions do
      [
        QueryManager.condition(param(:label), :eq, "x"),
        QueryManager.condition(param(:format), :eq, "y")
      ]
    end

    test "an and group joins its conditions with AND" do
      {sql, _} = grouped(:and_, false, conditions())

      assert sql =~ " AND "
      refute sql =~ " OR "
    end

    test "an or group joins its conditions with OR" do
      {sql, _} = grouped(:or_, false, conditions())

      assert sql =~ " OR "
    end

    test "a group nested inside a group keeps both logics" do
      nested = CoreQuery.new_filter(:or, false, conditions())

      {sql, _} =
        grouped(:and_, false, [QueryManager.condition(param(:description), :eq, "z"), nested])

      assert sql =~ " AND "
      assert sql =~ " OR "
    end

    test "negate wraps the whole group, not a single condition" do
      {sql, _} = grouped(:and_, true, conditions())

      assert sql =~ ~r/NOT \(\(.* AND .*\)\)/
    end

    test "negate on a nested group wraps only that group" do
      nested = CoreQuery.new_filter(:or, true, conditions())

      {sql, _} =
        grouped(:and_, false, [QueryManager.condition(param(:description), :eq, "z"), nested])

      assert sql =~ ~r/NOT \(.* OR .*\)/
    end

    test "two path conditions compose against the joined row" do
      {sql, _} =
        grouped(:or_, false, [
          QueryManager.condition(param(:label), :eq, "x", false, path()),
          QueryManager.condition(param(:format), :eq, "y", false, path())
        ])

      assert sql =~ " OR "
      assert sql =~ "a1.\"data\""
    end
  end
end

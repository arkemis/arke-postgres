defmodule ArkePostgres.RepoCase do
  @moduledoc """
  Case template for tests that reach the database.

  Rows are rolled back by the Ecto sandbox, but the arke managers are global ETS and are
  not, so a test that registers an arke leaves it behind. Give arkes ids unique to the
  file rather than relying on teardown.

  DDL cannot run inside the sandbox transaction, and checking out with `sandbox: false`
  fights the shared owner. Tag a test `:unboxed` to put the repo in `:auto` for its
  duration instead, and clean up after it by hand.

  No query here emits an `ORDER BY` unless the test asks for one, so row order is whatever
  Postgres returns. Sort every multi-row assertion, through `ids/1` or `Enum.sort/1`.
  """

  use ExUnit.CaseTemplate

  alias Arke.Boundary.ArkeManager
  alias Arke.{LinkManager, QueryManager}

  using do
    quote do
      alias Arke.Boundary.{ArkeManager, ParameterManager}
      alias Arke.{LinkManager, QueryManager}
      alias ArkePostgres.Repo

      import ArkePostgres.RepoCase

      @project :test_schema
    end
  end

  setup tags do
    if tags[:unboxed] do
      Ecto.Adapters.SQL.Sandbox.mode(ArkePostgres.Repo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(ArkePostgres.Repo, :manual) end)
    else
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ArkePostgres.Repo, shared: not tags[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  @doc """
  Creates an arke carrying one string parameter, so units of it can hold data.

  A parameter has to be created inside the project and linked: the system parameters
  live in `:arke_system` and `LinkManager.add_node/4` resolves both ends within a single
  project.
  """
  def create_arke(id, parameter_id) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    string = ArkeManager.get(:string, :arke_system)

    {:ok, _} =
      QueryManager.create(:test_schema, arke_model, %{id: to_string(id), label: "Fixture #{id}"})

    {:ok, _} =
      QueryManager.create(:test_schema, string, %{
        id: to_string(parameter_id),
        label: to_string(parameter_id)
      })

    {:ok, _} =
      LinkManager.add_node(:test_schema, to_string(id), to_string(parameter_id), "parameter")

    ArkeManager.get(id, :test_schema)
  end

  def create_unit(arke, id, data \\ %{}) do
    {:ok, unit} = QueryManager.create(:test_schema, arke, Map.put(data, :id, to_string(id)))
    unit
  end

  def ids(units), do: units |> Enum.map(&to_string(&1.id)) |> Enum.sort()

  def schema_exists?(name), do: count_of("schemata", "schema_name = $1", [name]) == 1

  def table_exists?(schema, table),
    do: count_of("tables", "table_schema = $1 AND table_name = $2", [schema, table]) == 1

  defp count_of(relation, where, params) do
    %{rows: [[count]]} =
      ArkePostgres.Repo.query!(
        "SELECT count(*) FROM information_schema.#{relation} WHERE #{where}",
        params
      )

    count
  end
end

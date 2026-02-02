# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule ArkePostgres do
  alias Arke.Boundary.{GroupManager, ArkeManager}
  alias ArkePostgres.{Table, ArkeUnit, Query}

  def init() do
    case check_env() do
      {:ok, nil} ->
        try do
          projects =
            Query.get_project_record()
            |> Enum.sort_by(&(to_string(&1.id) == "arke_system"), :desc)

          Enum.each(projects, fn %{id: project_id} = _project ->
            start_managers(project_id)
          end)

          :ok
        rescue
          err in DBConnection.ConnectionError ->
            %{message: message, reason: reason} = err

            parsed_message = %{
              context: "db_connection_error",
              message: "error: #{err}, msg: #{message}"
            }

            IO.inspect(parsed_message, syntax_colors: [string: :red, atom: :cyan])
            :error

          err in Postgrex.Error ->
            %{message: message, postgres: %{code: code, message: postgres_message}} = err

            parsed_message = %{
              context: "postgrex_error",
              message: "#{message || postgres_message}"
            }

            IO.inspect(parsed_message, syntax_colors: [string: :red, atom: :cyan])
            :error
        end

      {:error, keys} ->
        print_missing_env(keys)
        :error
    end
  end

  def print_missing_env(keys) when is_list(keys) do
    for k <- keys do
      IO.puts("#{IO.ANSI.red()} error:#{IO.ANSI.reset()} env key #{k} not found.")
    end
  end

  def print_missing_env(keys), do: print_missing_env([keys])

  def check_env() do
    keys = ["DB_NAME", "DB_HOSTNAME", "DB_USER", "DB_PASSWORD"]

    key_map =
      Enum.reduce(keys, [], fn k, acc ->
        if System.get_env(k) == nil, do: [k | acc], else: acc
      end)

    with true <- length(key_map) != 0 do
      {:error, key_map}
    else
      _ -> {:ok, nil}
    end
  end

  defp start_managers(project_id) when is_binary(project_id),
    do: start_managers(String.to_atom(project_id))

  defp start_managers(project_id) do
    {parameters, arke_list, groups} = Query.get_manager_units(project_id)

    Arke.handle_manager(parameters, project_id, :parameter)
    Arke.handle_manager(arke_list, project_id, :arke)
    Arke.handle_manager(groups, project_id, :group)
  end

  def create(project, %{arke_id: arke_id} = unit) do
    arke = Arke.Boundary.ArkeManager.get(arke_id, project)

    case handle_create(project, arke, unit) do
      {:ok, unit} ->
        {:ok,
         Arke.Core.Unit.update(unit, metadata: Map.merge(unit.metadata, %{project: project}))}

      {:error, errors} ->
        {:error, handle_changeset_errros(errors)}
    end
  end

  defp handle_create(
         project,
         %{data: %{type: "table"}} = arke,
         %{data: data, metadata: metadata} = unit
       ) do
    # todo: remove once the project is not needed anymore
    data = data |> Map.merge(%{metadata: Map.delete(metadata, :project)}) |> data_as_klist
    Table.insert(project, arke, data)
    {:ok, unit}
  end

  defp handle_create(project, %{data: %{type: "arke"}} = arke, unit) do
    case ArkeUnit.insert(project, arke, unit) do
      {:ok, %{id: id, inserted_at: inserted_at, updated_at: updated_at}} ->
        {:ok,
         Arke.Core.Unit.update(unit, id: id, inserted_at: inserted_at, updated_at: updated_at)}

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp handle_create(proj, arke, unit) do
    {:error, "arke type not supported"}
  end

  def update(project, %{arke_id: arke_id} = unit) do
    arke = Arke.Boundary.ArkeManager.get(arke_id, project)
    {:ok, unit} = handle_update(project, arke, unit)
  end

  def handle_update(
        project,
        %{data: %{type: "table"}} = arke,
        %{data: data, metadata: metadata} = unit
      ) do
    data =
      unit
      |> filter_primary_keys(false)
      # todo: remove once the project is not needed anymore
      |> Map.merge(%{metadata: Map.delete(metadata, :project)})
      |> data_as_klist

    where = unit |> filter_primary_keys(true) |> data_as_klist

    Table.update(project, arke, data, where)
    {:ok, unit}
  end

  def handle_update(project, %{data: %{type: "arke"}} = arke, unit) do
    ArkeUnit.update(project, arke, unit)
    {:ok, unit}
  end

  def handle_update(_, _, _) do
    {:error, "arke type not supported"}
  end

  def update_key(%{arke_id: arke_id, metadata: %{project: project}} = old_unit, new_unit) do
    arke = Arke.Boundary.ArkeManager.get(arke_id, project)
    {:ok, unit} = handle_update_key(arke, old_unit, new_unit)
  end

  def handle_update_key(
        %{data: %{type: "table"}} = arke,
        _old_unit,
        %{data: data, metadata: %{project: project} = metadata} = new_unit
      ) do
    data =
      new_unit
      |> filter_primary_keys(false)
      # todo: remove once the project is not needed anymore
      |> Map.merge(%{metadata: Map.delete(metadata, :project)})
      |> data_as_klist

    where = new_unit |> filter_primary_keys(true) |> data_as_klist

    Table.update(project, arke, data, where)
    {:ok, new_unit}
  end

  def handle_update_key(
        %{data: %{type: "arke"}} = arke,
        old_unit,
        new_unit
      ) do
    ArkeUnit.update_key(arke, old_unit, new_unit)
    {:ok, new_unit}
  end

  def handle_update_key(_arke, _old_unit, _new_unit) do
    {:error, "arke type not supported"}
  end

  def delete(project, %{arke_id: arke_id} = unit) do
    arke = Arke.Boundary.ArkeManager.get(arke_id, project)
    handle_delete(project, arke, unit)
  end

  defp handle_delete(project, %{data: %{type: "table"}} = arke, %{metadata: metadata} = unit) do
    metadata = Map.delete(metadata, :project)

    where = unit |> filter_primary_keys(true) |> Map.put_new(:metadata, metadata) |> data_as_klist

    case Table.delete(project, arke, where) do
      {:ok, _} -> {:ok, nil}
      {:error, msg} -> {:error, msg}
    end
  end

  defp handle_delete(project, %{data: %{type: "arke"}} = arke, unit) do
    case ArkeUnit.delete(project, arke, unit) do
      {:ok, _} -> {:ok, nil}
      {:error, msg} -> {:error, msg}
    end
  end

  defp handle_delete(_, _, _) do
    {:error, "arke type not supported"}
  end

  defp filter_primary_keys(
         %{arke_id: arke_id, metadata: %{project: project}} = unit,
         is_primary \\ true
       ) do
    arke = Arke.Boundary.ArkeManager.get(arke_id, project)

    parameters =
      Enum.filter(Arke.Boundary.ArkeManager.get_parameters(arke), fn %{data: param_data} ->
        param_data.is_primary != is_primary
      end)

    unit.data |> remove_parameters(parameters)
  end

  defp remove_parameter(data, parameter) do
    Map.delete(data, parameter.id)
  end

  defp remove_parameters(data, parameters) do
    Enum.reduce(parameters, data, fn f, new_struct ->
      remove_parameter(new_struct, f)
    end)
  end

  def data_as_klist(data) do
    Enum.to_list(data)
  end

  defp handle_changeset_errros(errors) when is_binary(errors), do: errors

  defp handle_changeset_errros(errors) do
    Enum.map(errors, fn {field, detail} ->
      "#{field}: #{render_detail(detail)}"
    end)
  end

  defp render_detail({message, values}) do
    Enum.reduce(values, message, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  defp render_detail(message) do
    message
  end

  ######################################################################################################################

  def create_project(%{arke_id: :arke_project, id: id} = _unit) do
    try do
      sql = "CREATE SCHEMA \"#{id}\""
      Ecto.Adapters.SQL.query(ArkePostgres.Repo, sql, [])
      Ecto.Migrator.run(ArkePostgres.Repo, :up, all: true, prefix: id)
      :ok
    rescue
      err in DBConnection.ConnectionError ->
        IO.inspect("DBConnection.ConnectionError")
        %{message: message} = err
        parsed_message = %{context: "db_connection_error", message: "#{message}"}
        IO.inspect(parsed_message, syntax_colors: [string: :red, atom: :cyan])
        :error

      err in Postgrex.Error ->
        IO.inspect("Postgrex.Error")
        %{message: message, postgres: %{code: code, message: postgres_message}} = err
        parsed_message = %{context: "postgrex_error", message: "#{message || postgres_message}"}
        IO.inspect(parsed_message, syntax_colors: [string: :red, atom: :cyan])
        :error

      err ->
        IO.inspect("uncatched error")
        IO.inspect(err)
        :error
    end
  end

  # TODO handle exception
  def create_project(_), do: nil

  def delete_project(%{arke_id: :arke_project, id: id} = unit) do
    sql = "DROP SCHEMA \"#{id}\" CASCADE"
    Ecto.Adapters.SQL.query(ArkePostgres.Repo, sql, [])
  end

  # TODO handle exception
  def delete_project(_), do: nil
end

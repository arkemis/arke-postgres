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

defmodule ArkePostgres.ArkeUnit do
  alias Arke.Boundary.ArkeManager
  import Ecto.Query
  alias Arke.Utils.ErrorGenerator, as: Error

  @record_fields [:id, :data, :metadata, :inserted_at, :updated_at]

  def insert(project, arke, %{data: data} = unit) do
    row = [
      id: handle_id(unit.id),
      arke_id: Atom.to_string(unit.arke_id),
      data: encode_unit_data(arke, data),
      metadata: unit.metadata,
      inserted_at: unit.inserted_at,
      updated_at: unit.updated_at
    ]

    case ArkePostgres.Repo.insert(ArkePostgres.Tables.ArkeUnit.changeset(Enum.into(row, %{})),
           prefix: project
         ) do
      {:ok, record} ->
        {:ok, record}

      {:error, changeset} ->
        {:error, changeset.errors}
    end
  end

  defp handle_id(id) when is_nil(id), do: UUID.uuid1()
  defp handle_id(id) when is_atom(id), do: Atom.to_string(id)
  defp handle_id(id) when is_binary(id), do: id
  # TODO handle error
  defp handle_id(id), do: id

  def update(project, arke, %{data: data} = unit, where \\ []) do
    where = Keyword.put_new(where, :arke_id, Atom.to_string(unit.arke_id))
    where = Keyword.put_new(where, :id, Atom.to_string(unit.id))

    row = [
      data: encode_unit_data(arke, data),
      metadata: Map.delete(unit.metadata, :project),
      updated_at: unit.updated_at
    ]

    query = from("arke_unit", where: ^where, update: [set: ^row])
    ArkePostgres.Repo.update_all(query, [], prefix: project)
  end

  def update_key(
        arke,
        old_unit,
        %{data: data, metadata: %{project: project} = metadata} = unit,
        where \\ []
      ) do
    where = Keyword.put_new(where, :arke_id, Atom.to_string(unit.arke_id))
    where = Keyword.put_new(where, :id, Atom.to_string(unit.id))

    diff_keys = diff_keys(old_unit.data, data, Map.keys(data))

    encoded_data = encode_unit_data(arke, diff_keys)

    # Build the jsonb_set operations for each changed key
    data_dynamic =
      Enum.reduce(encoded_data, dynamic([u], u.data), fn {param_id, new_value}, acc ->
        dynamic(
          [u],
          fragment(
            "jsonb_set(?, ?, ?::jsonb, true)",
            ^acc,
            ^[to_string(param_id)],
            ^new_value
          )
        )
      end)

    query =
      from(u in "arke_unit",
        where: ^where,
        update: [
          set: [
            data: ^data_dynamic,
            metadata: ^Map.delete(unit.metadata, "project"),
            updated_at: ^unit.updated_at
          ]
        ]
      )

    ArkePostgres.Repo.update_all(query, [], prefix: project)
  end

  def delete(project, arke, unit) do
    where = [arke_id: Atom.to_string(arke.id), id: Atom.to_string(unit.id)]
    query = from(a in "arke_unit", where: ^where)

    case ArkePostgres.Repo.delete_all(query, prefix: project) do
      {0, nil} ->
        Error.create(:delete, "item not found")

      _ ->
        {:ok, nil}
    end
  end

  def format_arke_unit_record(record) do
    Enum.reduce(record, Keyword.new(), fn {k, v}, new_record ->
      add_field_to_formatted_record(k, v, new_record)
    end)
  end

  defp add_field_to_formatted_record(:data = _key, unit_data, record) do
    Enum.reduce(decode_unit_data(unit_data), record, fn {k, v}, new_record ->
      Keyword.put(new_record, String.to_existing_atom(k), v)
    end)
  end

  defp add_field_to_formatted_record(key, value, record) do
    Keyword.put(record, key, value)
  end

  def encode_unit_data(arke, data) do
    Enum.reduce(data, %{}, fn {key, value}, new_map ->
      parameter = ArkeManager.get_parameter(arke, key)
      update_encoded_unit_data(parameter, new_map, value)
    end)
  end

  defp update_encoded_unit_data(%{data: %{only_runtime: true}}, data, _), do: data

  defp update_encoded_unit_data(%{id: id}, data, value),
    do:
      Map.put_new(data, Atom.to_string(id), %{
        :value => value,
        :datetime => Arke.Utils.DatetimeHandler.now(:datetime)
      })

  defp update_encoded_unit_data(_, data, _), do: data

  def decode_unit_data(data) do
    Enum.reduce(data, %{}, fn {key, arke_value}, new_map ->
      Map.put(new_map, key, get_unit_field_value(arke_value))
    end)
  end

  defp get_unit_field_value(arke_value) when is_map(arke_value) do
    Map.get(arke_value, "value", nil)
  end

  defp get_unit_field_value(arke_value) do
    arke_value
  end

  defp pop_datetime(data, key) do
    {datetime, data} = Map.pop(data, key, Arke.Utils.DatetimeHandler.now(:datetime))
    {datetime || Arke.Utils.DatetimeHandler.now(:datetime), data}
  end

  defp pop_map(data, key) do
    {map, data} = Map.pop(data, key, %{})
    {map || %{}, data}
  end

  def diff_keys(old_data, new_data, keys) do
    Enum.reduce(new_data, [], fn {key, value}, acc ->
      if key in keys and old_data[key] != value do
        [{key, value}] ++ acc
      else
        acc
      end
    end)
  end
end

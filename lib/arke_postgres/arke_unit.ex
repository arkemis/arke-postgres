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
  import Ecto.Query, only: [from: 2]
  alias Arke.Utils.ErrorGenerator, as: Error

  @record_fields [:id, :data, :metadata, :inserted_at, :updated_at]
  @chunk_size 5000

  def insert(project, arke, unit_list, opts \\ []) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{unit_list: updated_unit_list, records: records} =
      Enum.reduce(unit_list, %{unit_list: [], records: []}, fn unit, acc ->
        id = handle_id(unit.id)

        updated_unit =
          unit |> Map.put(:id, id) |> Map.put(:inserted_at, now) |> Map.put(:updated_at, now)

        acc
        |> Map.put(:unit_list, [updated_unit | acc.unit_list])
        |> Map.put(:records, [
          %{
            id: id,
            arke_id: Atom.to_string(unit.arke_id),
            data: encode_unit_data(arke, unit.data),
            metadata: unit.metadata,
            inserted_at: now,
            updated_at: now
          }
          | acc.records
        ])
      end)

    {total_count, all_inserted} =
      Stream.chunk_every(records, @chunk_size)
      |> Enum.reduce({0, []}, fn chunk, {count_acc, inserted_acc} ->
        case ArkePostgres.Repo.insert_all(
               ArkePostgres.Tables.ArkeUnit,
               chunk,
               prefix: project,
               returning: true
             ) do
          {chunk_count, chunk_inserted} ->
            {count_acc + chunk_count, inserted_acc ++ chunk_inserted}
        end
      end)

    case total_count do
      0 ->
        {:error, Error.create(:insert, "no records inserted")}

      count ->
        inserted_ids = Enum.map(all_inserted, & &1.id)

        {valid, errors} =
          Enum.split_with(updated_unit_list, fn unit ->
            unit.id in inserted_ids
          end)

        case opts[:bulk] do
          true -> {:ok, count, valid, errors}
          _ -> {:ok, List.first(valid)}
        end
    end
  end

  defp handle_id(id) when is_nil(id), do: UUID.uuid1()
  defp handle_id(id) when is_atom(id), do: Atom.to_string(id)
  defp handle_id(id) when is_binary(id), do: id
  # TODO handle error
  defp handle_id(id), do: id

  def update(project, arke, unit_list, opts) do
    records =
      Enum.map(unit_list, fn unit ->
        %{
          id: to_string(unit.id),
          arke_id: to_string(arke.id),
          data: encode_unit_data(arke, unit.data),
          metadata: Map.delete(unit.metadata, :project),
          inserted_at: DateTime.to_naive(unit.inserted_at) |> NaiveDateTime.truncate(:second),
          updated_at: DateTime.to_naive(unit.updated_at)
        }
      end)

    {total_count, all_updated} =
      Stream.chunk_every(records, @chunk_size)
      |> Enum.reduce({0, []}, fn chunk, {count_acc, updated_acc} ->
        case ArkePostgres.Repo.insert_all(
               ArkePostgres.Tables.ArkeUnit,
               chunk,
               prefix: project,
               on_conflict: {:replace_all_except, [:id]},
               conflict_target: :id,
               returning: true
             ) do
          {chunk_count, chunk_updated} ->
            {count_acc + chunk_count, updated_acc ++ chunk_updated}
        end
      end)

    case total_count do
      0 ->
        {:error, Error.create(:update, "no records updated")}

      count ->
        updated_ids = Enum.map(all_updated, & &1.id)

        {valid, errors} =
          Enum.split_with(unit_list, fn unit ->
            to_string(unit.id) in updated_ids
          end)

        case opts[:bulk] do
          true -> {:ok, count, valid, errors}
          _ -> {:ok, List.first(valid)}
        end
    end
  end

  def delete(project, arke, unit_list) do
    query =
      from(a in "arke_unit",
        where: a.arke_id == ^Atom.to_string(arke.id),
        where: a.id in ^Enum.map(unit_list, &Atom.to_string(&1.id))
      )

    {total_count, _} =
      Stream.chunk_every(Enum.map(unit_list, &Atom.to_string(&1.id)), @chunk_size)
      |> Enum.reduce({0, nil}, fn chunk, {count_acc, _} ->
        query =
          from(a in "arke_unit",
            where: a.arke_id == ^Atom.to_string(arke.id),
            where: a.id in ^chunk
          )

        case ArkePostgres.Repo.delete_all(query, prefix: project) do
          {chunk_count, nil} -> {count_acc + chunk_count, nil}
        end
      end)

    case total_count do
      0 -> Error.create(:delete, "item not found")
      _ -> {:ok, nil}
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
end

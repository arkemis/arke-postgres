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

defmodule ArkePostgres.Query do
  import Ecto.Query
  require IEx
  alias Arke.Utils.DatetimeHandler, as: DatetimeHandler

  @record_fields [:id, :arke_id, :data, :metadata, :inserted_at, :updated_at]

  def generate_query(
        %{filters: filters, orders: orders, offset: offset, limit: limit} = arke_query,
        action
      ) do
    paths = extract_paths(filters) ++ extract_paths(orders)

    base_query(arke_query, action)
    |> handle_paths_join(paths)
    |> handle_filters(filters)
    |> handle_orders(orders)
    |> handle_offset(offset)
    |> handle_limit(limit)
  end

  def execute(query, :raw),
    do: Ecto.Adapters.SQL.to_sql(:all, ArkePostgres.Repo, generate_query(query, :raw))

  def execute(query, :all) do
    generate_query(query, :all)
    |> ArkePostgres.Repo.all(prefix: query.project)
    |> generate_units(query.arke, query.project)
  end

  def execute(query, :one) do
    record = generate_query(query, :one) |> ArkePostgres.Repo.one(prefix: query.project)
    init_unit(record, query.arke, query.project)
  end

  def execute(query, :count) do
    generate_query(query, :count) |> ArkePostgres.Repo.one(prefix: query.project)
  end

  def execute(query, :pseudo_query), do: generate_query(query, :pseudo_query)

  def get_column(column), do: get_column(column, false)

  def get_column(%{data: %{persistence: "arke_parameter"}} = parameter, joined),
    do: get_arke_column(parameter, joined)

  def get_column(%{data: %{persistence: "table_column"}} = parameter, _joined),
    do: get_table_column(parameter)

  def remove_arke_system(metadata, project_id) when project_id == :arke_system, do: metadata

  def remove_arke_system(metadata, project_id) do
    case Map.get(metadata, "project") do
      "arke_system" -> Map.delete(metadata, "project")
      _ -> metadata
    end
  end

  def merge_unit_metadata(params, units, project_id) do
    Enum.map(params, fn param ->
      unit_metadata = Map.get(units, param.child_id, %{})
      merge_metadata = Map.merge(param.metadata, unit_metadata, fn _k, _v1, v2 -> v2 end)
      Map.put(param, :metadata, remove_arke_system(merge_metadata, project_id))
    end)
  end

  def get_manager_units(project_id) do
    arke_link = %{
      id: :arke_link,
      data: %{parameters: [%{id: :type}, %{id: :child_id}, %{id: :parent_id}, %{id: :metadata}]}
    }

    links =
      from(q in table_query(arke_link, nil), where: q.type in ["parameter", "group"])
      |> ArkePostgres.Repo.all(prefix: project_id)

    parameter_links = Enum.filter(links, fn x -> x.type == "parameter" end)
    group_links = Enum.filter(links, fn x -> x.type == "group" end)

    parameters_id = Arke.Utils.DefaultData.get_parameters_id()

    list_arke_id = Arke.Utils.DefaultData.get_arke_id()

    unit_list =
      from(q in base_query(), where: q.arke_id in ^list_arke_id)
      |> ArkePostgres.Repo.all(prefix: project_id)

    units_map = Map.new(unit_list, &{&1.id, &1.metadata})
    parameter_links = merge_unit_metadata(parameter_links, units_map, project_id)

    parameters =
      parse_parameters(Enum.filter(unit_list, fn u -> u.arke_id in parameters_id end), project_id)

    arke_list =
      parse_arke_list(
        Enum.filter(unit_list, fn u -> u.arke_id == "arke" end),
        parameter_links
      )

    groups =
      parse_groups(
        Enum.filter(unit_list, fn u -> u.arke_id == "group" end),
        group_links
      )

    {parameters, arke_list, groups}
  end

  def get_project_record() do
    unit_list =
      from(q in base_query(), where: q.arke_id == "arke_project")
      |> ArkePostgres.Repo.all(prefix: "arke_system")
  end

  defp parse_arke_list(arke_list, parameter_links) do
    # todo: remove the string to atom when everything would become string
    Enum.reduce(arke_list, [], fn %{id: id, metadata: metadata} = unit, new_arke_list ->
      params =
        Enum.reduce(
          Enum.filter(parameter_links, fn x -> x.parent_id == id end),
          [],
          fn p, new_params ->
            [
              %{
                id: String.to_atom(p.child_id),
                metadata:
                  Enum.reduce(p.metadata, %{}, fn {key, val}, acc ->
                    Map.put(acc, String.to_atom(key), val)
                  end)
              }
              | new_params
            ]
          end
        )

      updated_data =
        Enum.reduce(unit.data, %{}, fn {k, db_data}, acc ->
          Map.put(acc, String.to_atom(k), db_data["value"])
        end)
        |> Map.put(:id, id)
        |> Map.put(:metadata, metadata)
        |> Map.update(:parameters, [], fn current -> params ++ current end)

      [updated_data | new_arke_list]
    end)
  end

  defp parse_parameters(parameter_list, project_id) do
    Enum.reduce(parameter_list, [], fn %{id: id, arke_id: arke_id, metadata: metadata} = unit,
                                       new_parameter_list ->
      parsed_metadata = remove_arke_system(metadata, project_id)

      updated_data =
        Enum.reduce(unit.data, %{}, fn {k, db_data}, acc ->
          Map.put(acc, String.to_atom(k), db_data["value"])
        end)
        |> Map.put(:id, id)
        |> Map.put(:type, arke_id)
        |> Map.put(:metadata, parsed_metadata)

      [updated_data | new_parameter_list]
    end)
  end

  defp parse_groups(groups, group_links) do
    Enum.reduce(groups, [], fn %{id: id, metadata: metadata} = unit, new_groups ->
      arke_list =
        Enum.reduce(
          Enum.filter(group_links, fn x -> x.parent_id == id end),
          [],
          fn p, new_params ->
            [%{id: String.to_atom(p.child_id), metadata: p.metadata} | new_params]
          end
        )

      updated_data =
        Enum.reduce(unit.data, %{}, fn {k, db_data}, acc ->
          Map.put(acc, String.to_atom(k), db_data["value"])
        end)
        |> Map.put(:id, id)
        |> Map.put(:metadata, metadata)
        |> Map.update(:arke_list, [], fn db_arke_list ->
          Enum.reduce(db_arke_list, [], fn key, acc ->
            case Enum.find(arke_list, fn %{id: id, metadata: _metadata} ->
                   to_string(id) == key
                 end) do
              nil ->
                [key | acc]

              data ->
                [data | acc]
            end
          end)
        end)

      [updated_data | new_groups]
    end)
  end

  ######################################################################################################################
  # PRIVATE FUNCTIONS ##################################################################################################
  ######################################################################################################################
  defp base_query(%{arke: %{data: %{type: "table"}, id: id} = arke} = _arke_query, action),
    do: table_query(arke, action)

  defp base_query(%{link: nil} = _arke_query, action), do: arke_query(action)

  defp base_query(
         %{
           link: %{unit: %{id: link_id}, depth: depth, direction: direction, type: type},
           project: project
         } = _arke_query,
         action
       ),
       do:
         get_nodes(
           project,
           action,
           [to_string(link_id)],
           depth,
           direction,
           type
         )

  defp base_query(
         %{
           link: %{unit: unit_list, depth: depth, direction: direction, type: type},
           project: project
         } = _arke_query,
         action
       )
       when is_list(unit_list) do
    get_nodes(
      project,
      action,
      Enum.map(unit_list, fn unit -> to_string(unit.id) end),
      depth,
      direction,
      type
    )
  end

  defp base_query(), do: from("arke_unit", select: ^@record_fields)

  defp arke_query(:count), do: from("arke_unit", select: count("*"))
  defp arke_query(_action), do: from("arke_unit", select: ^@record_fields)

  defp table_query(%{id: id, data: data} = arke, action) do
    table_name = Atom.to_string(id)

    fields =
      Enum.reduce(data.parameters, [], fn %{id: parameter_id}, new_fields ->
        [parameter_id | new_fields]
      end)

    from(table_name, select: ^fields)
  end

  defp get_arke(project, %{arke_id: arke_id}, nil) when is_binary(arke_id),
    do: Arke.Boundary.ArkeManager.get(String.to_existing_atom(arke_id), project)

  defp get_arke(project, %{arke_id: arke_id}, nil) when is_atom(arke_id),
    do: Arke.Boundary.ArkeManager.get(arke_id, project)

  defp get_arke(project, %{arke_id: arke_id}, nil),
    do: Arke.Boundary.ArkeManager.get(String.to_existing_atom(arke_id), project)

  defp get_arke(project, %{arke_id: arke_id}, arke) when is_atom(arke),
    do: Arke.Boundary.ArkeManager.get(arke, project)

  defp get_arke(project, %{arke_id: arke_id}, arke) when is_binary(arke),
    do: Arke.Boundary.ArkeManager.get(String.to_existing_atom(arke), project)

  defp get_arke(_, %{arke_id: arke_id}, arke), do: arke
  defp get_arke(_, _data, arke), do: arke

  defp generate_units(data, arke, project) do
    Enum.reduce(data, [], fn d, units ->
      units ++ [init_unit(d, arke, project)]
    end)
  end

  def init_unit(nil, _, _), do: nil

  def init_unit(record, arke, project) do
    arke = get_arke(project, record, arke)
    {metadata, record} = Map.pop(record, :metadata, %{})
    {record_data, record} = Map.pop(record, :data, %{})

    record_data =
      Enum.map(arke.data.parameters, fn p ->
        {p.id, Map.get(record_data, Atom.to_string(p.id), nil)}
      end)
      |> Map.new()

    record = Map.put(record, :metadata, Map.merge(metadata, %{project: project}))
    record = Map.merge(record_data, record)
    Arke.Core.Unit.load(arke, record)
  end

  defp handle_paths_join(query, []), do: query

  defp handle_paths_join(query, paths) do
    conditions =
      Enum.reduce(paths, nil, fn path, acc ->
        condition = dynamic([q, j], ^get_column(List.first(path)) == j.id)
        if is_nil(acc), do: condition, else: dynamic([q, j], ^acc or ^condition)
      end)

    from(q in query, left_join: j in "arke_unit", on: ^conditions)
  end

  defp extract_paths(items) do
    items
    |> Enum.flat_map(&extract_path/1)
    |> Enum.reject(&(is_nil(&1) or length(&1) == 0))
    |> Enum.uniq()
  end

  def extract_path(%Arke.Core.Query.Filter{base_filters: base_filters}),
    do: Enum.flat_map(base_filters, &extract_path/1)

  def extract_path(%Arke.Core.Query.BaseFilter{path: path}), do: [path]
  def extract_path(%Arke.Core.Query.Order{path: path}), do: [path]

  def extract_path(_), do: []

  def handle_filters(query, filters) do
    Enum.reduce(filters, query, fn %{logic: logic, negate: negate, base_filters: base_filters},
                                   query ->
      clause = build_filter_clause(logic, base_filters) |> handle_negate_condition(negate)
      from(q in query, where: ^clause)
    end)
  end

  defp build_filter_clause(parent_logic, filters),
    do: build_filter_clause(nil, parent_logic, filters)

  defp build_filter_clause(clause, parent_logic, filters),
    do: Enum.reduce(filters, clause, &handle_clause(&1, &2, parent_logic))

  defp handle_clause(
         %Arke.Core.Query.Filter{logic: logic, base_filters: nested_filters},
         clause,
         parent_logic
       ),
       do:
         build_filter_clause(nil, logic, nested_filters)
         |> add_condition_to_clause(clause, parent_logic)

  defp handle_clause(
         %Arke.Core.Query.BaseFilter{
           parameter: parameter,
           operator: operator,
           value: value,
           negate: negate,
           path: []
         },
         clause,
         parent_logic
       ),
       do:
         parameter_condition(clause, parameter, value, operator, negate, parent_logic)
         |> add_condition_to_clause(clause, parent_logic)

  defp handle_clause(
         %Arke.Core.Query.BaseFilter{
           parameter: parameter,
           operator: operator,
           value: value,
           negate: negate,
           path: [path_parameter | _]
         },
         clause,
         parent_logic
       )
       when not is_nil(path_parameter),
       do:
         parameter_condition(clause, parameter, value, operator, negate, parent_logic, true)
         |> add_nested_condition_to_clause(clause, parent_logic)

  defp handle_clause(_, clause, _), do: clause

  defp parameter_condition(clause, parameter, value, operator, negate, logic, joined \\ nil) do
    column = get_column(parameter, joined)
    value = get_value(parameter, value)

    condition =
      if is_nil(value) or operator == :isnull do
        get_nil_query(parameter, column, negate, joined)
      else
        filter_query_by_operator(parameter, column, value, operator)
      end

    handle_negate_condition(condition, negate)
  end

  defp handle_negate_condition(condition, true), do: dynamic([q], not (^condition))
  defp handle_negate_condition(condition, false), do: condition

  defp add_condition_to_clause(condition, nil, _), do: dynamic([q], ^condition)
  defp add_condition_to_clause(condition, clause, :and), do: dynamic([q], ^clause and ^condition)
  defp add_condition_to_clause(condition, clause, :or), do: dynamic([q], ^clause or ^condition)

  defp add_nested_condition_to_clause(condition, nil, _), do: dynamic([_q, j], ^condition)

  defp add_nested_condition_to_clause(condition, clause, :and),
    do: dynamic([_q, j], ^clause and ^condition)

  defp add_nested_condition_to_clause(condition, clause, :or),
    do: dynamic([_q, j], ^clause or ^condition)

  defp handle_orders(query, orders) do
    order_by =
      Enum.reduce(orders, [], fn %{parameter: parameter, direction: direction, path: path},
                                 new_order_by ->
        joined = length(path) > 0
        column = get_column(parameter, joined)
        [{direction, column} | new_order_by]
      end)

    from(q in query, order_by: ^order_by)
  end

  defp handle_offset(query, offset) when is_nil(offset), do: query
  defp handle_offset(query, offset), do: from(q in query, offset: ^offset)

  defp handle_limit(query, limit) when is_nil(limit), do: query
  defp handle_limit(query, limit), do: from(q in query, limit: ^limit)

  defp get_table_column(%{id: id} = _parameter), do: dynamic([q], fragment("?", field(q, ^id)))

  defp get_arke_column(%{id: id, data: %{multiple: true}} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::jsonb", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, data: %{multiple: true}} = _parameter, _joined),
    do:
      dynamic([q], fragment("(? -> ? ->> 'value')::jsonb", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :string} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::text", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :string} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::text", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :atom} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::text", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :atom} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::text", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :boolean} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::boolean", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :boolean} = _parameter, _joined),
    do:
      dynamic(
        [q],
        fragment("(? -> ? ->> 'value')::boolean", field(q, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :datetime} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::timestamp", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :datetime} = _parameter, _joined),
    do:
      dynamic(
        [q],
        fragment("(? -> ? ->> 'value')::timestamp", field(q, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :date} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::date", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :date} = _parameter, _joined),
    do:
      dynamic(
        [q],
        fragment("(? -> ? ->> 'value')::date", field(q, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :time} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::time", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :time} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::time", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :integer} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::integer", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :integer} = _parameter, _joined),
    do:
      dynamic(
        [q],
        fragment("(? -> ? ->> 'value')::integer", field(q, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :float} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::float", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :float} = _parameter, _joined),
    do:
      dynamic([q], fragment("(? -> ? ->> 'value')::float", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :dict} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::JSON", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :dict} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::JSON", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :list} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::JSON", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :list} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::JSON", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :link} = _parameter, true),
    do:
      dynamic(
        [_q, ..., j],
        fragment("(? -> ? ->> 'value')::text", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :link} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::text", field(q, :data), ^Atom.to_string(id)))

  defp get_arke_column(%{id: id, arke_id: :dynamic} = _parameter, true),
    do:
      dynamic(
        [_, ..., j],
        fragment("(? -> ? ->> 'value')::text", field(j, :data), ^Atom.to_string(id))
      )

  defp get_arke_column(%{id: id, arke_id: :dynamic} = _parameter, _joined),
    do: dynamic([q], fragment("(? -> ? ->> 'value')::text", field(q, :data), ^Atom.to_string(id)))

  defp get_value(_parameter, value) when is_nil(value), do: value
  defp get_value(_parameter, value) when is_list(value), do: value
  defp get_value(_parameter, value) when is_map(value), do: value

  defp get_value(parameter, value) when is_atom(value) and not is_boolean(value),
    do: get_value(parameter, Atom.to_string(value))

  defp get_value(%{id: id, arke_id: :string} = _parameter, value) when is_binary(value), do: value
  defp get_value(%{id: id, arke_id: :string} = _parameter, value), do: Kernel.inspect(value)

  defp get_value(%{id: id, arke_id: :integer} = _parameter, value) when is_number(value),
    do: value

  defp get_value(%{id: id, arke_id: :integer} = _parameter, value) when is_binary(value) do
    case Integer.parse(value) do
      {value, _remainder} -> value
      _ -> raise("Parameter(#{id}) value not valid")
    end
  end

  defp get_value(%{id: id, arke_id: :integer} = parameter, value) when is_list(value),
    do: parse_number_list(parameter, value, fn v -> is_integer(v) end)

  defp get_value(%{id: id, arke_id: :float} = _parameter, value) when is_number(value), do: value

  defp get_value(%{id: id, arke_id: :float} = _parameter, value) when is_binary(value) do
    case Float.parse(value) do
      {value, _remainder} -> value
      _ -> raise("Parameter(#{id}) value not valid")
    end
  end

  defp get_value(%{id: id, arke_id: :float} = parameter, value) when is_list(value),
    do: parse_number_list(parameter, value, fn v -> is_number(v) end)

  defp get_value(%{id: id, arke_id: :boolean} = _parameter, true), do: true
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "true"), do: true
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "True"), do: true
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, 1), do: true
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "1"), do: true
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, false), do: false
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "false"), do: false
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "False"), do: false
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, 0), do: false
  defp get_value(%{id: id, arke_id: :boolean} = _parameter, "0"), do: false

  defp get_value(%{id: id, arke_id: :boolean} = _parameter, _),
    do: raise("Parameter(#{id}) value not valid")

  defp get_value(%{id: id, arke_id: :datetime} = _parameter, value) do
    case DatetimeHandler.parse_datetime(value) do
      {:ok, parsed_datetime} -> parsed_datetime
      {:error, _msg} -> raise("Parameter(#{id}) value not valid")
    end
  end

  defp get_value(%{id: id, arke_id: :date} = _parameter, value) do
    case DatetimeHandler.parse_date(value) do
      {:ok, parsed_date} -> parsed_date
      {:error, _msg} -> raise("Parameter(#{id}) value not valid")
    end
  end

  defp get_value(%{id: id, arke_id: :time} = _parameter, value) do
    case DatetimeHandler.parse_time(value) do
      {:ok, parsed_time} -> parsed_time
      {:error, _msg} -> raise("Parameter(#{id}) value not valid")
    end
  end

  defp get_value(%{id: id, arke_id: :dict} = _parameter, value), do: value
  defp get_value(%{id: id, arke_id: :list} = _parameter, value), do: value
  defp get_value(%{id: id, arke_id: :link} = _parameter, value), do: value
  defp get_value(%{id: id, arke_id: :dynamic} = _parameter, value), do: value
  defp get_value(%{id: id}, value), do: raise("Parameter(#{id}) value not valid")

  defp parse_number_list(parameter, value, func) do
    case Enum.all?(value, &is_binary(&1)) do
      true ->
        Enum.map(value, &get_value(parameter, &1))

      false ->
        # check if all the values are numbers, otherwise throw an error
        case Enum.all?(value, &func.(&1)) do
          true -> Enum.map(value, &get_value(parameter, &1))
          false -> raise("Parameter(#{parameter.id}) value not valid")
        end
    end
  end

  defp get_nil_query(%{id: id} = _parameter, column, false, false),
    do:
      dynamic(
        [q],
        fragment("? IS NULL AND (?.data \\? ?)", ^column, q, ^Atom.to_string(id))
      )

  defp get_nil_query(%{id: id} = _parameter, column, false, true),
    do:
      dynamic(
        [q, ..., j],
        fragment("? IS NULL AND (?.data \\? ?)", ^column, j, ^Atom.to_string(id))
      )

  defp get_nil_query(%{id: id} = _parameter, column, true, _joined),
    do:
      dynamic(
        [q],
        is_nil(^column)
      )

  defp filter_query_by_operator(%{data: %{multiple: true}}, column, value, :eq),
    do: dynamic([q], fragment("jsonb_exists(?, ?)", ^column, ^value))

  defp filter_query_by_operator(parameter, column, value, :eq),
    do: dynamic([q], ^column == ^value)

  defp filter_query_by_operator(parameter, column, value, :contains),
    do: dynamic([q], like(^column, fragment("?", ^("%" <> value <> "%"))))

  defp filter_query_by_operator(parameter, column, value, :icontains),
    do: dynamic([q], ilike(^column, fragment("?", ^("%" <> value <> "%"))))

  defp filter_query_by_operator(parameter, column, value, :endswith),
    do: dynamic([q], like(^column, fragment("?", ^("%" <> value))))

  defp filter_query_by_operator(parameter, column, value, :iendswith),
    do: dynamic([q], ilike(^column, fragment("?", ^("%" <> value))))

  defp filter_query_by_operator(parameter, column, value, :startswith),
    do: dynamic([q], like(^column, fragment("?", ^(value <> "%"))))

  defp filter_query_by_operator(parameter, column, value, :istartswith),
    do: dynamic([q], ilike(^column, fragment("?", ^(value <> "%"))))

  defp filter_query_by_operator(parameter, column, value, :lte),
    do: dynamic([q], ^column <= ^value)

  defp filter_query_by_operator(parameter, column, value, :lt), do: dynamic([q], ^column < ^value)
  defp filter_query_by_operator(parameter, column, value, :gt), do: dynamic([q], ^column > ^value)

  defp filter_query_by_operator(parameter, column, value, :gte),
    do: dynamic([q], ^column >= ^value)

  defp filter_query_by_operator(parameter, column, value, :in),
    do: dynamic([q], ^column in ^value)

  defp filter_query_by_operator(parameter, column, value, _), do: dynamic([q], ^column == ^value)

  # defp filter_query_by_operator(query, key, value, "between"), do: from q in query, where: column_table(q, ^key) == ^value

  ######################################################################################################################
  # ARKE LINK ##########################################################################################################
  ######################################################################################################################

  @raw_cte_query """
  (
    WITH RECURSIVE tree(depth, parent_id, type, child_id, metadata, starting_unit) AS (
      SELECT 0, parent_id, type, child_id, metadata, ? FROM ?.arke_link WHERE ? = ANY(?)
      UNION SELECT
        depth + 1,
        ?.arke_link.parent_id,
        ?.arke_link.type,
        ?.arke_link.child_id,
        ?.arke_link.metadata,
        tree.starting_unit
      FROM
        ?.arke_link JOIN tree
        ON ?.arke_link.? = tree.?
      WHERE
       depth < ?
    )
    SELECT * FROM tree ORDER BY depth
  )
  """

  def get_nodes(project, action, unit_id, depth, direction, type) when is_list(unit_id) do
    project = get_project(project)
    {link_field, tree_field} = get_fields_by_direction(direction)
    where_field = get_where_field_by_direction(direction) |> get_where_condition_by_type(type)
    get_link_query(action, project, unit_id, link_field, tree_field, depth, where_field)
  end

  def get_nodes(project, action, unit_id, depth, direction, type),
    do: get_nodes(project, action, [unit_id], depth, direction, type)

  defp get_project(project) when is_atom(project), do: Atom.to_string(project)
  defp get_project(project), do: project
  defp get_fields_by_direction(:child), do: {"parent_id", "child_id"}
  defp get_fields_by_direction(:parent), do: {"child_id", "parent_id"}

  defp get_where_field_by_direction(:child),
    do: dynamic([a, cte], a.id == fragment("?", field(cte, ^:child_id)))

  defp get_where_field_by_direction(:parent),
    do: dynamic([a, cte], a.id == fragment("?", field(cte, ^:parent_id)))

  defp get_where_condition_by_type(condition, nil), do: condition

  defp get_where_condition_by_type(condition, type),
    do: dynamic([a, cte], ^condition and cte.type == ^type)

  defp get_where_field_by_direction(:parent),
    do: dynamic([a, cte], a.id == fragment("?", field(cte, ^:parent_id)))

  defp get_link_query(:count, project, unit_id_list, link_field, tree_field, depth, where_field) do
    from(a in "arke_unit",
      left_join:
        cte in fragment(
          @raw_cte_query,
          literal(^link_field),
          literal(^project),
          literal(^link_field),
          ^unit_id_list,
          literal(^project),
          literal(^project),
          literal(^project),
          literal(^project),
          literal(^project),
          literal(^project),
          literal(^link_field),
          literal(^tree_field),
          ^depth
        ),
      where: ^where_field,
      select: count([a.id, cte.starting_unit], :distinct)
    )
  end

  defp get_link_query(_action, project, unit_id_list, link_field, tree_field, depth, where_field) do
    q =
      from(
        r in from(a in "arke_unit",
          left_join:
            cte in fragment(
              @raw_cte_query,
              literal(^link_field),
              literal(^project),
              literal(^link_field),
              ^unit_id_list,
              literal(^project),
              literal(^project),
              literal(^project),
              literal(^project),
              literal(^project),
              literal(^project),
              literal(^link_field),
              literal(^tree_field),
              ^depth
            ),
          where: ^where_field,
          distinct: [a.id, cte.starting_unit],
          select: %{
            id: a.id,
            arke_id: a.arke_id,
            data: a.data,
            metadata: a.metadata,
            inserted_at: a.inserted_at,
            updated_at: a.updated_at,
            depth: cte.depth,
            link_metadata: cte.metadata,
            link_type: cte.type,
            starting_unit: cte.starting_unit
          }
        )
      )

    from(x in subquery(q), select: x)
  end
end

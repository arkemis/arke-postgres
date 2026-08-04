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

defmodule Mix.Tasks.ArkePostgres.CreateProject do
  use Mix.Task

  @shortdoc "Creates a new project"

  @moduledoc """
  Creates a new project in the database.

  ## Examples

      $ mix arke_postgres.create_project --id my_project
      $ mix arke_postgres.create_project --id my_project --description "My project description"

  ## Command line options

  * `--id` - The id of the project to create
  * `--label` - The label of the project to create
  * `--description` - The description of the project to create
  """

  @impl true
  def run([]) do
    Mix.shell().error(
      "Project ID is missing. Please provide an id for the project by passing --id project_id"
    )
  end

  def run(args) do
    case ArkePostgres.check_env() do
      {:ok, _} ->
        [:postgrex, :ecto_sql]
        |> Enum.each(&Application.ensure_all_started/1)

        case ArkePostgres.Repo.start_link() do
          {:ok, pid} ->
            args |> parse_args() |> create_project()
            Process.exit(pid, :normal)
            :ok

          {:error, _} ->
            args |> parse_args() |> create_project()
            :ok
        end

      {:error, keys} ->
        ArkePostgres.print_missing_env(keys)
    end
  end

  defp create_project([{:id, id} | _] = opts) do
    Mix.shell().info("--- Creating schema for #{id}--- ")
    ArkePostgres.create_project(%{arke_id: :arke_project, id: id})

    Mix.shell().info("--- Creating arke_project for #{id}--- ")
    label = opts[:label] || String.capitalize(id) |> String.replace("_", " ") |> String.trim()
    description = opts[:description] || "Arke for the schema #{id}"
    now = Arke.Utils.DatetimeHandler.now(:datetime)

    data = %{
      label: %{value: label, datetime: now},
      description: %{value: description, datetime: now},
      type: %{value: "postgres_schema", datetime: now},
      persistence: %{value: "arke_parameter", datetime: now}
    }

    row = [
      id: id,
      arke_id: "arke_project",
      data: data,
      metadata: %{},
      inserted_at: now,
      updated_at: now
    ]

    case ArkePostgres.Repo.insert(ArkePostgres.Tables.ArkeUnit.changeset(Enum.into(row, %{})),
           prefix: "arke_system"
         ) do
      {:ok, record} ->
        {:ok, record}

      {:error, changeset} ->
        {:error, changeset.errors}
    end
  end

  defp create_project(_) do
    Mix.shell().error(
      "Project ID is missing. Please provide an id for the project by passing --id project_id"
    )
  end

  defp parse_args(args) do
    {options, _} =
      OptionParser.parse!(args, strict: [id: :string, label: :string, description: :string])

    options
  end
end

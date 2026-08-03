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
defmodule Mix.Tasks.ArkePostgres.CreateMember do
  alias Arke.QueryManager
  alias Arke.Boundary.ArkeManager
  use Mix.Task

  @shortdoc "Creates a new project"

  @moduledoc """
  Creates a new super admin member for the given project.
  If no username/password are provided then a default member admin/admin will be created if no other admin exists

  ## Examples

      $ mix arke_postgres.create_member my_project my_username mypassword

  Is equivalent to:
      $ mix arke_postgres.create_member --project my_project --username my_username --password mypassword

  ## Options

    * `--project` - The id of the project where to create the member
    * `--username` - The username of the member
    * `--password` - The password of the member
    * `--email` - The email of the member
  """

  @switches [
    project: :string,
    username: :string,
    password: :string,
    email: :string
  ]

  @impl true
  def run(argv) do
    case ArkePostgres.check_env() do
      {:ok, _} ->
        [:postgrex, :ecto_sql, :arke_auth, :arke, :arke_postgres]
        |> Enum.each(&Application.ensure_all_started/1)

        case ArkePostgres.Repo.start_link() do
          {:ok, pid} ->
            parse_options(argv)
            Process.exit(pid, :normal)

          {:error, _} ->
            parse_options(argv)
        end

        :ok

      {:error, keys} ->
        ArkePostgres.print_missing_env(keys)
    end
  end

  defp parse_options(argv) do
    case OptionParser.parse!(argv, strict: @switches) do
      {[], _opts} ->
        Mix.Tasks.Help.run(["arke_postgres.create_member"])

      {data, _opts} ->
        project = Keyword.fetch!(data, :project)
        username = Keyword.get(data, :username, "admin")
        password = Keyword.get(data, :password, "admin")
        check_user(String.to_atom(project), username, password, data)
    end
  end

  defp check_user(project_id, username, password, opts) do
    case QueryManager.get_by(project: :arke_system, arke_id: :user, username: username) do
      nil -> create_user(project_id, username, password, opts)
      %Arke.Core.Unit{} = user -> create_member(project_id, user)
    end
  end

  defp create_user(project_id, username, password, opts) do
    user_model = ArkeManager.get(:user, :arke_system)
    email = Keyword.get(opts, :email, "#{username}@bar.com")
    data = %{username: username, password: password, email: email, type: "super_admin"}

    with {:ok, user} <- QueryManager.create(:arke_system, user_model, data),
         {:ok, _member} <- create_member(project_id, user) do
      IO.inspect("member #{username} created", syntax_colors: [string: :cyan])
      :ok
    else
      {:error, msg} ->
        IO.inspect(msg)
        :ok
    end
  end

  defp create_member(project_id, user) do
    case ArkeManager.get(:super_admin, project_id) do
      nil ->
        IO.inspect("super_admin is missing", syntax_colors: [string: :red])
        :ok

      model ->
        case QueryManager.get_by(
               project: project_id,
               arke_id: :super_admin,
               arke_system_user: user.id
             ) do
          nil ->
            QueryManager.create(project_id, model, arke_system_user: user.id)

          _ ->
            IO.inspect("member already exists", syntax_colors: [string: :red])
            :ok
        end
    end
  end
end

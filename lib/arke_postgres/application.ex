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

defmodule ArkePostgres.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ArkePostgres.Repo, [show_sensitive_data_on_connection_error: true]}
      # Starts a worker by calling: ArkePostgres.Worker.start_link(arg)
      # {ArkePostgres.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArkePostgres.Supervisor]

    link = Supervisor.start_link(children, opts)

    case ArkePostgres.init() do
      :error -> System.halt(0)
      _ -> link
    end
  end

  # defp init_arke_postgres()
end

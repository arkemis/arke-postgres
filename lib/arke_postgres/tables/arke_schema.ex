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

defmodule ArkePostgres.Tables.ArkeSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @arke_schema_fields ~w[id label metadata active]a

  @primary_key {:id, :string, []}
  schema "arke_schema" do
    field(:label, :string)
    field(:metadata, :map, default: %{})
    field(:active, :boolean, default: true)
    field(:type, :string, default: "arke")

    timestamps()
  end

  def changeset(args \\ []) do
    %__MODULE__{}
    |> cast(args, @arke_schema_fields)
    |> validate_required(@arke_schema_fields)
  end
end

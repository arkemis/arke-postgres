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

defmodule ArkePostgres.Tables.ArkeUnit do
  use Ecto.Schema
  import Ecto.Changeset

  @arke_record_fields ~w[id arke_id data metadata]a
  @timestamps ~w[inserted_at updated_at]a

  @primary_key {:id, :string, []}
  schema "arke_unit" do
    field(:arke_id, :string)
    field(:data, :map)
    field(:metadata, :map, default: %{})
    timestamps()
  end

  # TODO: add insert_all validation

  def changeset(args \\ []) do
    %__MODULE__{}
    |> cast(args, @arke_record_fields)
    |> validate_required(@arke_record_fields)
    |> unique_constraint(:id, name: "arke_unit_pkey", message: "id already exists")
  end
end

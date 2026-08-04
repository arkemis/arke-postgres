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

defmodule ArkePostgres.ArkeLink do
  use Ecto.Schema
  import Ecto.Changeset

  @arke_link_fields ~w[type parent_id child_id metadata]a

  @foreign_key_type :string
  schema "arke_link" do
    field(:type, :string, default: "link")
    belongs_to(:parent_id, ArkePostgres.Tables.ArkeUnit, primary_key: true)
    belongs_to(:child_id, ArkePostgres.Tables.ArkeUnit, primary_key: true)
    field(:metadata, :map, default: %{})
  end

  def changeset(args \\ []) do
    %__MODULE__{}
    |> cast(args, @arke_link_fields)
    |> validate_required(@arke_link_fields)
  end
end

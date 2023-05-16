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

defmodule ArkePostgres.Tables.ArkeSchemaField do
  use Ecto.Schema
  import Ecto.Changeset

  @arke_schema_field_fields ~w[arke_schema_id arke_parameter_id metadata]a

  @foreign_key_type :string
  schema "arke_schema_field" do
    belongs_to(:arke_schema, ArkePostgres.ArkeSchema, primary_key: true)
    belongs_to(:arke_field, ArkePostgres.ArkeField, primary_key: true)
    field(:metadata, :map, default: %{})
  end
end

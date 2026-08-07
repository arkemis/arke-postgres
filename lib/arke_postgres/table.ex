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

defmodule ArkePostgres.Table do
  import Ecto.Query, only: [from: 2]
  alias Arke.Utils.ErrorGenerator, as: Error

  def get_all(project, schema, fields, where \\ []) do
    query = from(Atom.to_string(schema.id), select: ^fields, where: ^where)
    ArkePostgres.Repo.all(query, prefix: project)
  end

  def get_by(project, schema, fields, where) do
    query = from(Atom.to_string(schema.id), select: ^fields, where: ^where)
    ArkePostgres.Repo.one(query, prefix: project)
  end

  def insert(project, schema, data) do
    case ArkePostgres.Repo.insert_all(Atom.to_string(schema.id), [data], prefix: project) do
      {n, _} when n > 0 -> {:ok, nil}
      _ -> Error.create(:insert, "no row inserted")
    end
  end

  def update(project, schema, data, where \\ []) do
    query = from(Atom.to_string(schema.id), where: ^where, update: [set: ^data])

    case ArkePostgres.Repo.update_all(query, [], prefix: project) do
      {0, _} -> Error.create(:update, "item not found")
      {_, _} -> {:ok, nil}
    end
  end

  def delete(project, schema, where) do
    query = from(a in Atom.to_string(schema.id), where: ^where)

    case ArkePostgres.Repo.delete_all(query, prefix: project) do
      {0, nil} -> Error.create(:delete, "item not found")
      _ -> {:ok, nil}
    end
  end
end

import Config

config :arke_postgres, ecto_repos: [ArkePostgres.Repo]

config :arke_postgres, ArkePostgres.Repo,
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("DB_NAME") || "arke_postgres_test",
  hostname: System.get_env("DB_HOSTNAME") || "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :arke,
  persistence: %{
    arke_postgres: %{
      create: &ArkePostgres.create/2,
      update: &ArkePostgres.update/2,
      update_key: &ArkePostgres.update_key/2,
      delete: &ArkePostgres.delete/2,
      execute_query: &ArkePostgres.Query.execute/2,
      create_project: &ArkePostgres.create_project/1,
      delete_project: &ArkePostgres.delete_project/1,
      repo: ArkePostgres.Repo,
      init: &ArkePostgres.init/0
    }
  }

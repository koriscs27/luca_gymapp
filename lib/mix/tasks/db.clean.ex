defmodule Mix.Tasks.Db.Clean do
  use Mix.Task

  @shortdoc "Truncates all public tables for a clean dev/test database"

  @moduledoc """
  Clears all rows from public tables (except `schema_migrations`) and resets identities.

      mix db.clean

  This task is only available in `:dev` and `:test` environments.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    ensure_allowed_env!()

    tables = list_public_tables()

    case tables do
      [] ->
        Mix.shell().info("No tables to clean.")

      _ ->
        truncate_tables(tables)
        Mix.shell().info("Database cleaned. Truncated #{length(tables)} tables.")
    end
  end

  defp ensure_allowed_env! do
    if Mix.env() not in [:dev, :test] do
      Mix.raise("mix db.clean is only allowed in dev/test environments.")
    end
  end

  defp list_public_tables do
    query = """
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename <> 'schema_migrations'
    ORDER BY tablename
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(LucaGymapp.Repo, query, [])
    Enum.map(rows, &List.first/1)
  end

  defp truncate_tables(tables) do
    quoted_tables =
      tables
      |> Enum.map(&~s("public"."#{&1}"))
      |> Enum.join(", ")

    sql = "TRUNCATE TABLE #{quoted_tables} RESTART IDENTITY CASCADE"

    Ecto.Adapters.SQL.query!(LucaGymapp.Repo, sql, [])
  end
end

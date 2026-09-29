defmodule ArkePostgres.BootTest do
  @moduledoc """
  A failed boot must stop the node with a non-zero status, so that a container runtime or a
  release script sees the failure. Each test boots the application in a separate `mix run`.
  """

  use ExUnit.Case, async: false

  @env [
    {"DB_NAME", "arke_boot_test"},
    {"DB_HOSTNAME", "localhost"},
    {"DB_USER", "postgres"},
    {"DB_PASSWORD", "postgres"}
  ]

  defp boot(env) do
    System.cmd("mix", ["run", "--no-compile", "-e", ~s|IO.puts("APP STARTED")|],
      env: [{"MIX_ENV", "test"} | env],
      stderr_to_stdout: true
    )
  end

  test "a missing env key fails the boot" do
    {output, status} = boot(List.keyreplace(@env, "DB_NAME", 0, {"DB_NAME", nil}))

    assert output =~ "env key DB_NAME not found"
    refute output =~ "APP STARTED"
    assert status != 0
  end

  test "an unreachable database fails the boot with the connection error" do
    {output, status} =
      boot(List.keyreplace(@env, "DB_HOSTNAME", 0, {"DB_HOSTNAME", "arke-boot-test.invalid"}))

    assert output =~ "db_connection_error"
    refute output =~ "Protocol.UndefinedError"
    refute output =~ "APP STARTED"
    assert status != 0
  end
end

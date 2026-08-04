defmodule ArkePostgres.EnvTest do
  @moduledoc """
  `check_env/0` reads the real process environment, so these run without `async` and
  restore whatever they change.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @keys ~w[DB_NAME DB_HOSTNAME DB_USER DB_PASSWORD]

  defp without(key, fun) do
    original = System.get_env(key)
    System.delete_env(key)

    try do
      fun.()
    after
      if original, do: System.put_env(key, original)
    end
  end

  test "passes when every key is set" do
    assert {:ok, nil} = ArkePostgres.check_env()
  end

  test "reports the missing key" do
    without("DB_NAME", fn ->
      assert {:error, missing} = ArkePostgres.check_env()
      assert missing == ["DB_NAME"]
    end)
  end

  test "reports every missing key" do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)

    try do
      assert {:error, missing} = ArkePostgres.check_env()
      assert Enum.sort(missing) == Enum.sort(@keys)
    after
      Enum.each(original, fn {key, value} -> if value, do: System.put_env(key, value) end)
    end
  end

  test "restores cleanly so later tests still see the environment" do
    assert {:ok, nil} = ArkePostgres.check_env()
  end

  test "init refuses to run with an incomplete environment" do
    without("DB_NAME", fn ->
      assert capture_io(fn -> assert ArkePostgres.init() == :error end) =~ "DB_NAME"
    end)
  end
end

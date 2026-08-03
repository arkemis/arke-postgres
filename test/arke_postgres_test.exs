defmodule ArkePostgresTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "data_as_klist/1" do
    test "turns a map into a keyword list" do
      assert ArkePostgres.data_as_klist(%{id: "x", label: "y"}) == [id: "x", label: "y"]
    end

    test "leaves a keyword list alone" do
      assert ArkePostgres.data_as_klist(id: "x") == [id: "x"]
    end

    test "handles an empty map" do
      assert ArkePostgres.data_as_klist(%{}) == []
    end
  end

  describe "print_missing_env/1" do
    test "names every missing key" do
      output = capture_io(fn -> ArkePostgres.print_missing_env(["DB_NAME", "DB_USER"]) end)

      assert output =~ "DB_NAME"
      assert output =~ "DB_USER"
    end

    test "accepts a bare key" do
      assert capture_io(fn -> ArkePostgres.print_missing_env("DB_NAME") end) =~ "DB_NAME"
    end
  end
end

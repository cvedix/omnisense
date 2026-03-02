defmodule CVRWeb.ErrorJSONTest do
  use CVRWeb.ConnCase, async: true

  test "renders 404" do
    assert CVRWeb.ErrorJSON.render("404.json", %{}) == %{message: "not found"}
  end

  test "renders 500" do
    assert CVRWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end

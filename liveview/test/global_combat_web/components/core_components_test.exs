defmodule GlobalCombatWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.CoreComponents

  describe "input/1 (text)" do
    test "wires aria-invalid and aria-describedby to the paired error text when invalid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input
          id="account_email"
          name="account[email]"
          type="text"
          value=""
          errors={["is invalid"]}
        />
        """)

      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(id="account_email-error-0")
      assert html =~ ~s(role="alert")
      assert html =~ ~s(aria-describedby="account_email-error-0")
      assert html =~ "is invalid"
    end

    test "describes every error paragraph when a field has multiple errors" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input
          id="account_password"
          name="account[password]"
          type="password"
          value=""
          errors={["too short", "needs a digit"]}
        />
        """)

      assert html =~ ~s(aria-describedby="account_password-error-0 account_password-error-1")
      assert html =~ ~s(id="account_password-error-0")
      assert html =~ ~s(id="account_password-error-1")
    end

    test "omits aria-invalid/aria-describedby when there are no errors" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input id="account_email" name="account[email]" type="text" value="" />
        """)

      refute html =~ "aria-invalid"
      refute html =~ "aria-describedby"
    end
  end

  describe "input/1 (select)" do
    test "wires aria-invalid and aria-describedby when invalid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input
          id="account_role"
          name="account[role]"
          type="select"
          value=""
          options={[Admin: "admin"]}
          errors={["is invalid"]}
        />
        """)

      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(aria-describedby="account_role-error-0")
    end
  end
end

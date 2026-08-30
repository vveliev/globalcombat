defmodule GlobalCombatWeb.HomeHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.HomeHTML

  describe "account_link/1 chat-toggle button" do
    test "gives online players a distinct accessible name naming who they'd chat with" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <HomeHTML.account_link id={1} name="Alice" online?={true} viewer_id={2} />
        """)

      assert html =~ ~s[aria-label="Chat with Alice (online)"]
    end

    test "gives offline players a distinct accessible name naming who they'd chat with" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <HomeHTML.account_link id={1} name="Bob" online?={false} viewer_id={2} />
        """)

      assert html =~ ~s[aria-label="Chat with Bob (offline)"]
    end

    test "two different online players get two different accessible names" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <HomeHTML.account_link id={1} name="Alice" online?={true} viewer_id={3} />
        <HomeHTML.account_link id={2} name="Carol" online?={true} viewer_id={3} />
        """)

      assert html =~ ~s[aria-label="Chat with Alice (online)"]
      assert html =~ ~s[aria-label="Chat with Carol (online)"]
    end
  end
end

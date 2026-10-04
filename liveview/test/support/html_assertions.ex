defmodule GlobalCombatWeb.HTMLAssertions do
  @moduledoc """
  `LazyHTML` helpers for tests that check a rendered element's classes —
  AGENTS.md rules out matching against the raw HTML string, so tests parse
  the markup, select the element, and assert on its class tokens instead.
  """

  import ExUnit.Assertions

  @doc """
  Returns the class tokens of the one element held by `node` (a `LazyHTML`
  selection, e.g. from `LazyHTML.query/2` or `LazyHTML.filter/2`).

  Fails the test unless `node` holds exactly one element, so a selector that
  drifts to match nothing — or several elements whose classes would get
  merged — can't make a class assertion pass by accident.

      assert "lg:hidden" in (doc |> LazyHTML.query("details") |> classes())
  """
  def classes(%LazyHTML{} = node) do
    count = Enum.count(node)

    assert count == 1,
           "expected exactly one element to read classes from, got #{count}: " <>
             LazyHTML.to_html(node)

    node |> LazyHTML.attribute("class") |> Enum.flat_map(&String.split/1)
  end
end

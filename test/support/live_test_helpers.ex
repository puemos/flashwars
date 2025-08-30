defmodule FlashwarsWeb.LiveTestHelpers do
  @moduledoc """
  Tiny helpers to reduce LiveView test flakiness by waiting
  for elements to be present before interacting with them.
  """

  import Phoenix.LiveViewTest

  @doc """
  Wait until a CSS selector matches in the LiveView, up to `attempts`.

  Returns :ok when found, :timeout otherwise.
  """
  def wait_for_selector(lv, selector, attempts \\ 80, interval_ms \\ 25)
  def wait_for_selector(_lv, _selector, 0, _interval), do: :timeout
  def wait_for_selector(lv, selector, n, interval) when is_binary(selector) do
    if has_element?(lv, selector) do
      :ok
    else
      _ = render(lv)
      Process.sleep(interval)
      wait_for_selector(lv, selector, n - 1, interval)
    end
  end
end


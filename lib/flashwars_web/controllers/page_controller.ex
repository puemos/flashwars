defmodule FlashwarsWeb.PageController do
  use FlashwarsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

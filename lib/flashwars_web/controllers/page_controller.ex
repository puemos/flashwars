defmodule FlashwarsWeb.PageController do
  use FlashwarsWeb, :controller

  def home(conn, _params) do
    # If a user is already signed in, send them to their org experience
    if conn.assigns[:current_user] do
      target = FlashwarsWeb.AuthRedirects.path_for_user(conn.assigns.current_user)
      redirect(conn, to: target)
    else
      render(conn, :home)
    end
  end
end

defmodule FlashwarsWeb.Plugs.GuestId do
  @moduledoc "Ensures a stable guest_id is stored in session for anonymous users."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "guest_id") do
      nil ->
        gid = random_id()
        put_session(conn, "guest_id", gid)

      _ ->
        conn
    end
  end

  defp random_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end

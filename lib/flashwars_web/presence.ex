defmodule FlashwarsWeb.Presence do
  use Phoenix.Presence,
    otp_app: :flashwars,
    pubsub_server: Flashwars.PubSub
end

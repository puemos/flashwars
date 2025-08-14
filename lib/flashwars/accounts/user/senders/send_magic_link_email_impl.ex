defmodule Flashwars.Accounts.User.Senders.SendMagicLinkEmailImpl do
  @behaviour Flashwars.Accounts.User.Senders.SendMagicLinkEmail

  def deliver(user, token) do
    # In a real application, you would send an email here.
    # For now, we'll just return :ok.
    IO.puts("Sending magic link to #{user.email} with token: #{token}")
    :ok
  end
end

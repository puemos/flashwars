defmodule Flashwars.Accounts.User.Senders.SendMagicLinkEmail do
  @callback deliver(user :: Flashwars.Accounts.User.t(), token :: String.t()) ::
              :ok | {:error, any()}
end

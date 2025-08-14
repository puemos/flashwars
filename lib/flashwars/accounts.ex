defmodule Flashwars.Accounts do
  use Ash.Domain, otp_app: :flashwars, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Flashwars.Accounts.Token
    resource Flashwars.Accounts.User
    resource Flashwars.Accounts.ApiKey
  end
end

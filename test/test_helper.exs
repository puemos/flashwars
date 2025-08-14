ExUnit.start()

Mox.defmock(Flashwars.Accounts.User.Senders.SendMagicLinkEmailMock, for: Flashwars.Accounts.User.Senders.SendMagicLinkEmail)
Ecto.Adapters.SQL.Sandbox.mode(Flashwars.Repo, :manual)

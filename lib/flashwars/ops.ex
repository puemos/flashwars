defmodule Flashwars.Ops do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Ops.Notification
    resource Flashwars.Ops.AuditLog
  end

  alias Flashwars.Ops.{Notification, AuditLog}

  def notify(params, opts \\ []),
    do: Notification |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def audit(params, opts \\ []),
    do: AuditLog |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
end

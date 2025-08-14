defmodule Flashwars.Ops do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Ops.Notification do
      define :notify, action: :create
    end

    resource Flashwars.Ops.AuditLog do
      define :audit, action: :create
    end
  end
end

defmodule Flashwars.Org do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Org.Organization do
      define :create_organization, action: :create
    end

    resource Flashwars.Org.OrgMembership do
      define :add_member, action: :create
    end

    resource Flashwars.Org.OrgDomain do
      define :add_org_domain, action: :create
    end
  end
end

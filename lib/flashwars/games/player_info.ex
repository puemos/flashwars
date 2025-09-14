defmodule Flashwars.Games.PlayerInfo do
  use Ash.TypedStruct

  typed_struct do
    field :nickname, :string, allow_nil?: false
    # nil for guests
    field :user_id, :string, allow_nil?: true
    # nil for registered users
    field :guest_id, :string, allow_nil?: true
    field :score, :integer, default: 0
    field :joined_at, :utc_datetime, default: &DateTime.utc_now/0
    field :last_seen, :utc_datetime, default: &DateTime.utc_now/0
  end
end

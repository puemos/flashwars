defmodule Flashwars.Games.GameRoomConfig do
  use Ash.TypedStruct

  typed_struct do
    # Game settings
    field :rounds, :integer, default: 10
    field :types, {:array, :string}, default: ["multiple_choice"]
    field :time_limit_ms, :integer, allow_nil?: true
    field :intermission_ms, :integer, default: 10_000

    # Players data - map of player_key => PlayerInfo
    field :players, :map, default: %{}
  end
end

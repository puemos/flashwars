defmodule Flashwars.Games do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Games.GameRoom
    resource Flashwars.Games.GameRound
    resource Flashwars.Games.GameSubmission
  end

  alias Flashwars.Games.{GameRoom, GameSubmission}

  def create_game_room(params, opts \\ []),
    do: GameRoom |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def start_game(game_room, opts \\ []),
    do: game_room |> Ash.Changeset.for_update(:start_game, %{}, opts) |> Ash.update()

  def advance_state(game_room, new_state, opts \\ []),
    do:
      game_room
      |> Ash.Changeset.for_update(:advance_state, %{new_state: new_state}, opts)
      |> Ash.update()

  def end_game(game_room, opts \\ []),
    do: game_room |> Ash.Changeset.for_update(:end_game, %{}, opts) |> Ash.update()

  def submit(params, opts \\ []),
    do: GameSubmission |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
end

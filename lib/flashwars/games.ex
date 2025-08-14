defmodule Flashwars.Games do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Games.GameRoom do
      define :create_game_room, action: :create
      define :start_game, action: :start_game
      define :advance_state, action: :advance_state, args: [:new_state]
      define :end_game, action: :end_game
    end

    resource Flashwars.Games.GameRound

    resource Flashwars.Games.GameSubmission do
      define :submit, action: :create
    end
  end
end

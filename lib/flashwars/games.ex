defmodule Flashwars.Games do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Games.GameRoom do
      define :create_game_room, action: :create
      define :start_game, action: :start_game
      define :advance_state, action: :advance_state, args: [:new_state]
      define :end_game, action: :end_game
      define :update_config, action: :update_config
      define :set_player_info, action: :set_player_info, args: [:player_key, :player_info]
      define :get_game_room_by_id, action: :read, get_by: [:id]
      define :get_game_room_by_token, action: :with_link_token, get_by: [:link_token]
    end

    resource Flashwars.Games.GameRound do
      define :generate_round, action: :generate_for_room
      define :list_rounds, action: :read
      define :destroy_round, action: :destroy
    end

    resource Flashwars.Games.GameSubmission do
      define :submit, action: :create
      define :list_submissions, action: :read
      define :destroy_submission, action: :destroy
    end
  end
end

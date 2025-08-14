defmodule Flashwars.Games.TickerSupervisor do
  def start_ticker(game_room_id) do
    spec = {Flashwars.Games.GameTicker, [game_room_id: game_room_id]}
    DynamicSupervisor.start_child(Flashwars.GameTickerSupervisor, spec)
  end
end

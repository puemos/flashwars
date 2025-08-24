defmodule FlashwarsWeb.GameRoomLive.Duel do
  use FlashwarsWeb, :live_view

  alias Phoenix.PubSub
  require Ash.Query

  alias Flashwars.Games
  alias Flashwars.Games.{PlayerInfo, GameRoomConfig}
  alias FlashwarsWeb.Presence

  alias FlashwarsWeb.QuizComponents

  @topic_prefix "flash_wars:room:"

  # Load user from session if present; allow anonymous viewing
  on_mount {FlashwarsWeb.LiveUserAuth, :current_user}
  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_optional}

  # ============================================================================
  # LiveView Callbacks
  # ============================================================================

  def mount(%{"id" => id}, session, socket) do
    case Games.get_game_room_by_id(id, authorize?: false) do
      {:ok, room} ->
        if allowed_to_view?(room, socket.assigns.current_user) do
          setup_for_room(room, assign(socket, :guest_id, session["guest_id"]))
        else
          {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
        end

      _ ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def mount(%{"token" => token}, session, socket) do
    room =
      Games.list_game_rooms!(
        authorize?: false,
        query: [filter: [privacy: :link_only, link_token: token], limit: 1]
      )
      |> List.first()

    if room do
      setup_for_room(room, assign(socket, :guest_id, session["guest_id"]))
    else
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("start", _params, %{assigns: %{room: room, host?: true}} = socket) do
    actor = socket.assigns.current_user

    with {:ok, room} <- Games.start_game(room, actor: actor),
         {:ok, round} <-
           Games.generate_round(
             %{game_room_id: room.id, strategy: strategy_from(socket.assigns.settings)},
             actor: actor
           ) do
      PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{event: :new_round, round: round})

      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:current_round, round)
       |> assign(:answered?, false)
       |> assign(:round_closed?, false)
       |> assign(:selected_index, nil)
       |> assign(:reveal, nil)
       |> assign(:intermission_deadline_mono, nil)
       |> assign(:nicknames, socket.assigns.nicknames)
       |> assign(:my_name, socket.assigns.my_name)
       |> setup_round_timer()
       |> assign(:scoreboard, fetch_scoreboard(room, actor))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("start", _params, socket), do: {:noreply, socket}

  def handle_event("set_name", %{"name" => name_param}, socket) do
    name =
      case name_param do
        %{"name" => v} -> v
        %{:name => v} -> v
        v -> v
      end

    trimmed = String.trim(name || "")
    valid? = String.length(trimmed) >= 1 and String.length(trimmed) <= 24

    if not valid? do
      {:noreply, put_flash(socket, :error, "Name must be 1-24 characters")}
    else
      socket = apply_nickname(socket, trimmed)
      # Ask client to persist name locally
      {:noreply, Phoenix.LiveView.push_event(socket, "store_guest_name", %{name: trimmed})}
    end
  end

  # Receive stored name from client on mount/connect and apply it
  def handle_event("guest_name_loaded", %{"name" => name_param}, socket) do
    trimmed = String.trim(name_param || "")
    valid? = String.length(trimmed) >= 1 and String.length(trimmed) <= 24

    if not valid? do
      {:noreply, socket}
    else
      {:noreply, apply_nickname(socket, trimmed)}
    end
  end

  def handle_event("answer", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case {socket.assigns.current_user, socket.assigns.current_round} do
      {nil, nil} ->
        {:noreply, socket}

      {_, nil} ->
        {:noreply, socket}

      {actor, round} ->
        # If this client already knows the round is closed, ignore
        if socket.assigns.round_closed? do
          {:noreply, socket}
        else
          qd = round.question_data || %{}
          answer_index = qd[:answer_index] || qd["answer_index"] || 0
          choices = qd[:choices] || qd["choices"] || []
          selected = Enum.at(choices, idx)
          correct? = idx == answer_index

          # If we have an authenticated user, persist a submission.
          # Scoring is handled by the GameSubmission.create action.
          if actor do
            _res =
              Games.submit(
                %{
                  game_round_id: round.id,
                  answer: selected,
                  correct: correct?,
                  submitted_at: DateTime.utc_now()
                },
                actor: actor
              )
          end

          # Close the round on the first submission, reveal to everyone
          PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
            event: :round_closed,
            round_id: round.id,
            user_id: actor && actor.id,
            selected_index: idx,
            correct_index: answer_index,
            correct?: correct?
          })

          {:noreply,
           socket
           |> assign(:answered?, true)
           |> assign(:selected_index, idx)
           |> assign(:scoreboard, fetch_scoreboard(socket.assigns.room, actor))}
        end
    end
  end

  def handle_event("ready", %{"rid" => rid}, %{assigns: %{current_user: %{id: uid}}} = socket) do
    # Only allow during intermission for the same round id
    if socket.assigns.intermission_rid == rid do
      new_set = MapSet.put(socket.assigns.ready_user_ids, uid)

      PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
        event: :ready,
        rid: rid,
        user_id: uid
      })

      {:noreply, assign(socket, :ready_user_ids, new_set)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("ready", _params, socket), do: {:noreply, socket}

  def handle_event("override_next", %{"rid" => rid}, %{assigns: %{host?: true}} = socket) do
    send(self(), {:next_round, rid})
    {:noreply, socket}
  end

  def handle_event("override_next", _params, socket), do: {:noreply, socket}

  def handle_event("save_settings", %{"settings" => params}, socket) do
    actor = socket.assigns.current_user
    {config, privacy} = parse_settings(params, socket.assigns.room.config)

    case Games.update_config(socket.assigns.room, %{config: config, privacy: privacy},
           actor: actor
         ) do
      {:ok, room} ->
        {:noreply,
         socket
         |> assign(:room, room)
         |> assign(:settings, settings_from_room(room))
         |> put_flash(:info, "Settings saved")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save settings: #{inspect(reason)}")}
    end
  end

  def handle_event("restart", _params, %{assigns: %{host?: true}} = socket) do
    actor = socket.assigns.current_user
    rid = socket.assigns.room.id

    # Delete submissions and rounds for this room (org constraints checked internally)
    Games.list_submissions_for_room!(rid, authorize?: false)
    |> Enum.each(fn s -> Games.destroy_submission!(s, authorize?: false) end)

    Games.list_rounds_for_room!(rid, authorize?: false)
    |> Enum.each(fn r -> Games.destroy_round!(r, authorize?: false) end)

    {:ok, room} = Games.advance_state(socket.assigns.room, :lobby, actor: actor)

    {:noreply,
     socket
     |> assign(:room, room)
     |> assign(:current_round, nil)
     |> assign(:answered?, false)
     |> assign(:round_closed?, false)
     |> assign(:selected_index, nil)
     |> assign(:reveal, nil)
     |> assign(:final_scoreboard, nil)
     |> assign(:round_deadline_mono, nil)
     |> assign(:now_mono, nil)
     |> assign(:scoreboard, fetch_scoreboard(room, actor))}
  end

  def handle_event("restart", _params, socket), do: {:noreply, socket}

  # Host handles round close; ignore duplicates for same round
  def handle_info(
        %{
          event: :round_closed,
          round_id: rid,
          user_id: uid,
          selected_index: sidx,
          correct_index: aidx,
          correct?: correct?
        },
        %{assigns: %{host?: true}} = socket
      ) do
    case socket.assigns.current_round do
      # If we've already processed this close (intermission_rid set), ignore duplicates
      %{id: ^rid} = _round when socket.assigns.intermission_rid == rid ->
        {:noreply, socket}

      %{id: ^rid} = _round ->
        {:noreply, apply_round_closed(socket, rid, uid, sidx, aidx, correct?)}

      _ ->
        {:noreply, socket}
    end
  end

  # Non-hosts also ignore duplicate close messages for same round
  def handle_info(
        %{
          event: :round_closed,
          round_id: rid,
          user_id: uid,
          selected_index: sidx,
          correct_index: aidx,
          correct?: correct?
        },
        socket
      ) do
    case socket.assigns.current_round do
      %{id: ^rid} when socket.assigns.intermission_rid == rid ->
        {:noreply, socket}

      %{id: ^rid} ->
        {:noreply, apply_round_closed(socket, rid, uid, sidx, aidx, correct?)}

      _ ->
        {:noreply, socket}
    end
  end

  # Handle player info updates from other players
  def handle_info(
        %{event: :player_info_update, player_key: key, player_info: info},
        %{assigns: %{host?: true}} = socket
      ) do
    socket = update_player_info(socket, key, info)
    {:noreply, socket}
  end

  def handle_info(%{event: :player_info_update}, socket), do: {:noreply, socket}

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, presence_list_safe(socket.assigns.topic))}
  end

  def handle_info({:time_up, rid}, %{assigns: %{host?: true}} = socket) do
    case socket.assigns.current_round do
      %{id: ^rid} = round ->
        qd = round.question_data || %{}
        answer_index = qd[:answer_index] || qd["answer_index"] || 0

        PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
          event: :round_closed,
          round_id: round.id,
          user_id: nil,
          selected_index: nil,
          correct_index: answer_index,
          correct?: false
        })

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:next_round, rid}, %{assigns: %{host?: true}} = socket) do
    case socket.assigns.current_round do
      %{id: ^rid} ->
        actor = socket.assigns.current_user
        limit = socket.assigns.settings[:rounds] || 10

        if socket.assigns.current_round.number >= limit do
          with {:ok, room} <- Games.end_game(socket.assigns.room, actor: actor) do
            # Inform everyone
            PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{event: :game_over})
            {:noreply, assign(socket, :room, room)}
          else
            _ -> {:noreply, socket}
          end
        else
          with {:ok, round} <-
                 Games.generate_round(
                   %{
                     game_room_id: socket.assigns.room.id,
                     strategy: strategy_from(socket.assigns.settings)
                   },
                   actor: actor
                 ) do
            PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
              event: :new_round,
              round: round
            })

            {:noreply,
             socket
             |> assign(:current_round, round)
             |> assign(:answered?, false)
             |> assign(:round_closed?, false)
             |> assign(:selected_index, nil)
             |> assign(:reveal, nil)
             |> setup_round_timer()
             |> assign(:scoreboard, fetch_scoreboard(socket.assigns.room, actor))}
          else
            _ -> {:noreply, socket}
          end
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(%{event: :ready, rid: rid, user_id: uid}, socket) do
    if socket.assigns.intermission_rid == rid do
      new_set = MapSet.put(socket.assigns.ready_user_ids, uid)
      socket = assign(socket, :ready_user_ids, new_set)

      # Host: check threshold to maybe start early
      socket =
        if socket.assigns.host? do
          if threshold_met?(socket) do
            send(self(), {:next_round, rid})
          end

          socket
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%{event: :new_round, round: round}, socket) do
    {:noreply,
     socket
     |> assign(:current_round, round)
     |> assign(:answered?, false)
     |> assign(:round_closed?, false)
     |> assign(:selected_index, nil)
     |> assign(:reveal, nil)
     |> assign(:final_scoreboard, nil)
     |> assign(:intermission_deadline_mono, nil)
     |> assign(:intermission_rid, nil)
     |> assign(:ready_user_ids, MapSet.new())
     |> setup_round_timer()
     |> assign(:scoreboard, fetch_scoreboard(socket.assigns.room, socket.assigns.current_user))}
  end

  def handle_info(%{event: :game_over}, socket) do
    # Build final scoreboard including player info from room config
    base = fetch_scoreboard(socket.assigns.room, socket.assigns.current_user)
    player_entries = get_player_entries(socket.assigns.room)
    merged = merge_player_scores(base, player_entries)

    {:noreply,
     socket
     |> assign(:final_scoreboard, merged)
     |> assign(:room, %{socket.assigns.room | state: :ended, ended_at: DateTime.utc_now()})}
  end

  def handle_info(:tick, %{assigns: %{round_deadline_mono: nil}} = socket), do: {:noreply, socket}

  def handle_info(:tick, socket) do
    # Keep ticking while deadline set
    Process.send_after(self(), :tick, 1000)
    {:noreply, assign(socket, :now_mono, System.monotonic_time(:millisecond))}
  end

  def handle_info(:intermission_tick, %{assigns: %{intermission_deadline_mono: nil}} = socket),
    do: {:noreply, socket}

  def handle_info(:intermission_tick, socket) do
    Process.send_after(self(), :intermission_tick, 1000)
    {:noreply, assign(socket, :now_mono, System.monotonic_time(:millisecond))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Apply the common state changes when a round is closed, handling host vs non-host
  # behavior (host schedules next round and sets answered? based on who answered first).
  defp apply_round_closed(socket, rid, uid, sidx, aidx, correct?) do
    im = intermission_ms(socket.assigns.settings)

    if socket.assigns.host? do
      Process.send_after(self(), {:next_round, rid}, im)
    end

    socket =
      socket
      |> assign(:round_closed?, true)
      |> assign(:reveal, %{
        user_id: uid,
        selected_index: sidx,
        correct_index: aidx,
        correct?: correct?
      })
      |> assign(:intermission_rid, rid)
      |> assign(:ready_user_ids, MapSet.new())
      |> start_intermission_timer(im)
      |> assign(:round_deadline_mono, nil)
      |> assign(:intermission_deadline_mono, System.monotonic_time(:millisecond) + im)
      |> assign(:now_mono, nil)

    # Only the host should adjust :answered? here; non-hosts keep their current flag
    if socket.assigns.host? do
      assign(
        socket,
        :answered?,
        socket.assigns.current_user && socket.assigns.current_user.id == uid
      )
    else
      socket
    end
  end

  # Consolidated nickname apply logic used by both set_name and guest_name_loaded events.
  defp apply_nickname(socket, trimmed) do
    case socket.assigns.current_user do
      %{id: uid} ->
        player_key = "user_#{uid}"

        socket =
          if socket.assigns.host? do
            update_player_info(socket, player_key, %PlayerInfo{
              nickname: trimmed,
              user_id: to_string(uid),
              guest_id: nil,
              last_seen: DateTime.utc_now()
            })
          else
            PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
              event: :player_info_update,
              player_key: player_key,
              player_info: %PlayerInfo{
                nickname: trimmed,
                user_id: to_string(uid),
                guest_id: nil,
                last_seen: DateTime.utc_now()
              }
            })

            socket
          end

        _ =
          if presence_available?() do
            Presence.update(
              self(),
              socket.assigns.topic,
              to_string(uid),
              fn _ -> %{name: trimmed} end
            )
          end

        socket
        |> assign(:my_name, trimmed)
        |> assign(:nicknames, Map.put(socket.assigns.nicknames, uid, trimmed))

      _ ->
        guest_id = socket.assigns.guest_id || generate_guest_id()
        player_key = "guest_#{guest_id}"

        socket =
          if socket.assigns.host? do
            update_player_info(socket, player_key, %PlayerInfo{
              nickname: trimmed,
              user_id: nil,
              guest_id: guest_id,
              last_seen: DateTime.utc_now()
            })
          else
            PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
              event: :player_info_update,
              player_key: player_key,
              player_info: %PlayerInfo{
                nickname: trimmed,
                user_id: nil,
                guest_id: guest_id,
                last_seen: DateTime.utc_now()
              }
            })

            socket
          end

        _ =
          if presence_available?() and socket.assigns[:presence_key] do
            Presence.update(
              self(),
              socket.assigns.topic,
              socket.assigns.presence_key,
              fn _ -> %{name: trimmed} end
            )
          end

        assign(socket, :my_name, trimmed)
    end
  end

  defp allowed_to_view?(%{privacy: :public}, _user), do: true
  defp allowed_to_view?(_room, nil), do: false

  defp allowed_to_view?(room, %{id: uid}) do
    cond do
      room.host_id == uid -> true
      true -> org_member?(room.organization_id, uid)
    end
  end

  defp org_member?(org_id, user_id) do
    Flashwars.Org.member?(org_id, user_id)
  end

  defp setup_for_room(room, socket) do
    topic = topic(room.id)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Flashwars.PubSub, topic)

    # Load latest round without auth to support link-only guests from other orgs
    current_round =
      Games.get_latest_round_for_room!(room.id, authorize?: false)
      |> List.first()

    {:ok,
     socket
     |> assign(:page_title, "Duel · #{room.type}")
     |> assign(:room, room)
     |> assign(:topic, topic)
     |> assign(:current_round, current_round)
     |> assign(:answered?, false)
     |> assign(:round_closed?, false)
     |> assign(:selected_index, nil)
     |> assign(:reveal, nil)
     |> assign(:final_scoreboard, nil)
     |> assign(:round_deadline_mono, nil)
     |> assign(:intermission_deadline_mono, nil)
     |> assign(:now_mono, nil)
     |> assign(:nicknames, %{})
     |> assign(:my_name, nil)
     |> assign(:settings_form, Phoenix.Component.to_form(%{}, as: :settings))
     |> assign(
       :host?,
       socket.assigns.current_user && socket.assigns.current_user.id == room.host_id
     )
     |> assign(:scoreboard, fetch_scoreboard(room, socket.assigns.current_user))
     |> assign(:settings, settings_from_room(room))
     |> maybe_track_presence(topic)}
  end

  # Helper to update player info using the Ash action
  defp update_player_info(socket, player_key, player_info) do
    case Games.set_player_info(socket.assigns.room, player_key, player_info,
           actor: socket.assigns.current_user
         ) do
      {:ok, room} ->
        assign(socket, :room, room)

      _ ->
        socket
    end
  end

  defp maybe_track_presence(socket, topic) do
    pres_avail? = presence_available?()

    # Existing presences for display
    presences = if pres_avail?, do: presence_list_safe(topic), else: %{}

    # Persisted nickname and nicknames map from config
    persisted_name = find_my_persisted_nickname(socket.assigns.room, socket)
    nicknames = load_player_nicknames(socket.assigns.room, socket)

    # Track used names from presence and config to avoid collisions
    used_from_presence =
      presences
      |> Map.values()
      |> Enum.flat_map(fn %{metas: metas} -> Enum.map(metas, & &1[:name]) end)
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    used_from_config = nicknames |> Map.values() |> MapSet.new()
    used_names = MapSet.union(used_from_presence, used_from_config)

    socket =
      case {socket.assigns.current_user, persisted_name} do
        # Authenticated with saved nickname
        {%{id: uid}, name} when is_binary(name) ->
          socket
          |> assign(:my_name, name)
          |> assign(:nicknames, Map.put(nicknames, uid, name))

        # Authenticated without saved nickname yet
        {%{id: uid}, nil} ->
          if socket.assigns.room.host_id == uid do
            # Host: generate once and persist
            new_name = generate_playful_name(used_names)

            socket =
              update_player_info(socket, "user_#{uid}", %PlayerInfo{
                nickname: new_name,
                user_id: to_string(uid),
                guest_id: nil,
                last_seen: DateTime.utc_now()
              })

            nicknames2 = load_player_nicknames(socket.assigns.room, socket)

            socket
            |> assign(:my_name, new_name)
            |> assign(:nicknames, Map.put(nicknames2, uid, new_name))
          else
            # Non-host: stable fallback until user sets a name
            fallback = display_name(socket.assigns.current_user)

            socket
            |> assign(:my_name, fallback)
            |> assign(:nicknames, Map.put(nicknames, uid, fallback))
          end

        # Guests or no user
        _ ->
          socket
          |> assign(:my_name, persisted_name)
          |> assign(:nicknames, nicknames)
      end

    key = presence_key(socket.assigns.current_user, socket.assigns[:guest_id])

    if connected?(socket) and pres_avail? do
      meta = %{name: socket.assigns.my_name || display_name(socket.assigns.current_user)}
      _ = Presence.track(self(), topic, key, meta)
    end

    presences = if pres_avail?, do: presence_list_safe(topic), else: %{}

    socket
    |> assign(:presences, presences)
    |> assign(:ready_user_ids, MapSet.new())
    |> assign(:intermission_rid, nil)
    |> assign(:presence_key, key)
  end

  # Load player information, tolerant of structs or plain maps.
  defp load_player_nicknames(%{config: config}, _socket) do
    players = config.players || %{}

    Enum.reduce(players, %{}, fn
      {_k, %PlayerInfo{user_id: uid, nickname: nick}}, acc
      when is_binary(uid) and is_binary(nick) ->
        Map.put(acc, String.to_integer(uid), nick)

      {_k, %{} = pi}, acc ->
        uid = pi[:user_id] || pi["user_id"]
        nick = pi[:nickname] || pi["nickname"]

        if is_binary(uid) and is_binary(nick) do
          Map.put(acc, String.to_integer(uid), nick)
        else
          acc
        end

      _, acc ->
        acc
    end)
  rescue
    _ -> %{}
  end

  # Find my persisted nickname from player info, whether struct or map
  defp find_my_persisted_nickname(%{config: config}, socket) do
    players = config.players || %{}

    player_key =
      case socket.assigns.current_user do
        %{id: uid} ->
          "user_#{uid}"

        _ ->
          case socket.assigns[:guest_id] do
            nil -> nil
            gid -> "guest_#{gid}"
          end
      end

    case player_key && Map.get(players, player_key) do
      %PlayerInfo{nickname: nickname} ->
        nickname

      %{} = pi ->
        pi[:nickname] || pi["nickname"]

      _ ->
        nil
    end
  end

  defp presence_available? do
    Process.whereis(FlashwarsWeb.Presence) != nil
  end

  defp presence_list_safe(topic) do
    try do
      Presence.list(topic)
    rescue
      ArgumentError -> %{}
    end
  end

  defp presence_key(nil, guest_id) when is_binary(guest_id), do: "guest:" <> guest_id

  defp presence_key(nil, _),
    do: "anon:" <> Base.url_encode64(:crypto.strong_rand_bytes(4), padding: false)

  defp presence_key(%{id: uid}, _guest_id), do: to_string(uid)

  defp threshold_met?(socket) do
    present = map_size(socket.assigns.presences)
    ready = MapSet.size(socket.assigns.ready_user_ids)
    needed = max(1, trunc(Float.ceil(present * 0.6)))
    present > 0 and ready >= needed
  end

  defp topic(id), do: @topic_prefix <> to_string(id)

  defp fetch_scoreboard(_room, nil), do: []

  defp fetch_scoreboard(room, actor) do
    subs =
      Games.list_submissions_for_room!(room.id, actor: actor, load: [:user])

    subs
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, subs} ->
      total = Enum.reduce(subs, 0, fn s, acc -> acc + (s.score || 0) end)
      user = subs |> List.first() |> Map.get(:user)
      %{user_id: user_id, user: user, name: display_name(user), score: total}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp get_player_entries(%{config: config}) do
    players = config.players || %{}

    players
    |> Map.values()
    |> Enum.map(fn player_info ->
      %{
        user_id: if(player_info.user_id, do: String.to_integer(player_info.user_id), else: nil),
        user: nil,
        name: player_info.nickname,
        score: 0
      }
    end)
  rescue
    _ -> []
  end

  defp merge_player_scores(user_entries, player_entries) do
    # Merge players whose names are not present in user entries. Keep existing order by score.
    existing_names = MapSet.new(Enum.map(user_entries, & &1.name))

    new_player_entries =
      Enum.reject(player_entries, fn p -> MapSet.member?(existing_names, p.name) end)

    user_entries ++ new_player_entries
  end

  defp settings_from_room(%{config: config}) do
    %{
      rounds: config.rounds,
      types: config.types,
      time_limit_ms: config.time_limit_ms,
      intermission_ms: config.intermission_ms
    }
  end

  defp parse_settings(params, current_config) do
    rounds = parse_int(params["rounds"]) || 10
    types = params["types"] || []
    time_limit_ms = parse_int(params["time_limit_ms"])
    intermission_ms = parse_int(params["intermission_ms"]) || 10_000
    privacy = parse_privacy(params["privacy"]) || :private

    # Preserve existing players when updating settings
    existing_players = if current_config, do: current_config.players || %{}, else: %{}

    config = %GameRoomConfig{
      rounds: rounds,
      types: types,
      time_limit_ms: time_limit_ms,
      intermission_ms: intermission_ms,
      players: existing_players
    }

    {config, privacy}
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp parse_privacy(nil), do: nil
  defp parse_privacy(val) when is_binary(val), do: String.to_existing_atom(val)

  defp strategy_from(%{types: types}) do
    cond do
      Enum.member?(types, "multiple_choice") -> :multiple_choice
      true -> :multiple_choice
    end
  end

  defp invitation_link(room), do: "#{FlashwarsWeb.Endpoint.url()}/games/t/#{room.link_token}"

  defp intermission_ms(settings) do
    settings[:intermission_ms] || settings["intermission_ms"] || 10_000
  end

  defp start_intermission_timer(socket, _ms) do
    # kick off ticking for client countdown display
    Process.send_after(self(), :intermission_tick, 1000)
    socket |> assign(:now_mono, System.monotonic_time(:millisecond))
  end

  defp setup_round_timer(%{assigns: %{current_round: nil}} = socket), do: socket

  defp setup_round_timer(%{assigns: %{settings: settings}} = socket) do
    tl = settings[:time_limit_ms] || settings["time_limit_ms"]

    cond do
      is_integer(tl) and tl > 0 ->
        deadline = System.monotonic_time(:millisecond) + tl

        if socket.assigns.host? do
          Process.send_after(self(), {:time_up, socket.assigns.current_round.id}, tl)
        end

        # start ticking
        Process.send_after(self(), :tick, 1000)

        socket
        |> assign(:round_deadline_mono, deadline)
        |> assign(:now_mono, System.monotonic_time(:millisecond))

      true ->
        socket |> assign(:round_deadline_mono, nil) |> assign(:now_mono, nil)
    end
  end

  defp ms_remaining(nil, _now), do: nil

  defp ms_remaining(deadline, nil) when is_integer(deadline) do
    now = System.monotonic_time(:millisecond)
    max(deadline - now, 0)
  end

  defp ms_remaining(deadline, now) when is_integer(deadline) and is_integer(now) do
    max(deadline - now, 0)
  end

  defp display_name(nil), do: "Unknown"

  defp display_name(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp display_name(_), do: "Player"

  defp generate_guest_id do
    Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  @adjectives ~w(Brisk Clever Zippy Sly Jolly Witty Sunny Swift Cosmic Daring Jazzy Lively Quirky Rapid Snazzy)
  @animals ~w(Panda Falcon Tiger Koala Otter Fox Dolphin Llama Badger Eagle Gecko Panda Yak Corgi Puma)

  defp generate_playful_name(used_names) do
    base = Enum.random(@adjectives) <> " " <> Enum.random(@animals)
    ensure_unique_name(base, used_names)
  end

  defp ensure_unique_name(base, used_names) do
    if MapSet.member?(used_names, base) do
      2..999
      |> Enum.find_value(fn n ->
        candidate = base <> " " <> Integer.to_string(n)
        not MapSet.member?(used_names, candidate) && candidate
      end)
      |> case do
        nil -> base <> " " <> Integer.to_string(:rand.uniform(9999))
        other -> other
      end
    else
      base
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Duel Room
        <:subtitle>
          {@room.type} · {case @room.privacy do
            :private -> "Private"
            :link_only -> "Link access"
            :public -> "Public"
          end}
        </:subtitle>
        <:actions>
          <button :if={@host? && @room.state == :lobby} class="btn btn-primary" phx-click="start">
            Start Game
          </button>
          <button :if={@host? && @room.state == :ended} class="btn btn-secondary" phx-click="restart">
            Start New Game
          </button>
        </:actions>
      </.header>

      <% round_seconds =
        if @round_deadline_mono,
          do: round(Float.ceil((ms_remaining(@round_deadline_mono, @now_mono) || 0) / 1000.0)),
          else: nil

      round_pct =
        if @round_deadline_mono do
          rem = ms_remaining(@round_deadline_mono, @now_mono) || 0
          total = @settings.time_limit_ms || 1
          bar = if total <= 0, do: 0, else: max(min(total - rem, total), 0)
          if total <= 0, do: 0.0, else: bar * 100.0 / total
        else
          nil
        end %>
      <QuizComponents.hud
        :if={@current_round && @room.state != :ended}
        round={@current_round.number}
        rounds={@settings.rounds}
        seconds_left={round_seconds}
        pct={round_pct}
        players_count={map_size(@presences)}
      />

      <div :if={@host? && @room.state == :lobby} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h3 class="card-title">Game Settings</h3>

          <.form for={@settings_form} id="duel-settings-form" phx-submit="save_settings">
            <div class="grid grid-cols-1 sm:grid-cols-4 gap-4">
              <.input name="settings[rounds]" label="Rounds" type="number" value={@settings.rounds} />
              <.input
                name="settings[time_limit_ms]"
                label="Time limit (ms)"
                type="number"
                value={@settings.time_limit_ms}
              />
              <.input
                name="settings[intermission_ms]"
                label="Intermission (ms)"
                type="number"
                value={@settings.intermission_ms}
              />
              <.input
                name="settings[privacy]"
                label="Privacy"
                type="select"
                options={[{"Private", "private"}, {"Link only", "link_only"}, {"Public", "public"}]}
                value={Atom.to_string(@room.privacy)}
              />
            </div>

            <div class="mt-4">
              <label class="block text-sm font-medium">Question Types</label>
              <div class="flex gap-4 mt-2">
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="settings[types][]"
                    value="multiple_choice"
                    checked={Enum.member?(@settings.types, "multiple_choice")}
                  /> Multiple choice
                </label>
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="settings[types][]"
                    value="true_false"
                    checked={Enum.member?(@settings.types, "true_false")}
                  /> True/False
                </label>
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="settings[types][]"
                    value="free_text"
                    checked={Enum.member?(@settings.types, "free_text")}
                  /> Free text
                </label>
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="settings[types][]"
                    value="matching"
                    checked={Enum.member?(@settings.types, "matching")}
                  /> Matching
                </label>
              </div>
            </div>

            <div :if={@room.privacy == :link_only} class="mt-4">
              <label class="block text-sm font-medium">Copy Invitation Link</label>
              <div class="flex gap-2 items-center mt-2">
                <input class="input flex-1" type="text" readonly value={invitation_link(@room)} />
                <button
                  id="copy-invite"
                  type="button"
                  class="btn btn-secondary"
                  phx-hook="CopyToClipboard"
                  data-text={invitation_link(@room)}
                >
                  Copy
                </button>
              </div>
            </div>

            <div class="mt-4 flex justify-end">
              <.button class="btn btn-primary">Save Settings</.button>
            </div>
          </.form>
        </div>
      </div>

      <div :if={!@host? && @room.state == :lobby} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h3 class="card-title">Your Game Name</h3>
          <.form for={%{}} as={:name} id="duel-name-form" phx-submit="set_name" phx-hook="GuestName">
            <div class="flex gap-2">
              <input
                class="input input-bordered flex-1 font-semibold"
                name="name[name]"
                type="text"
                value={@my_name || ""}
                placeholder="e.g., Speedy"
              />
              <button class="btn btn-primary" type="submit">Set Name</button>
            </div>
            <p class="text-xs opacity-70 mt-2">Shown to everyone during the game</p>
          </.form>
        </div>
      </div>

      <div :if={@room.state == :lobby} class="card bg-base-100 mb-4">
        <div class="card-body">
          <h4 class="font-semibold">Players in Lobby</h4>
          <QuizComponents.lobby_players presences={@presences} />
        </div>
      </div>

      <div :if={@current_round && @room.state != :ended} id="duel-round" class="space-y-4">
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="text-sm opacity-70">
              Question {@current_round.number} of {@settings.rounds}
            </div>

            <h3 class="text-xl font-semibold">
              {@current_round.question_data[:prompt] || @current_round.question_data["prompt"] || ""}
            </h3>

            <QuizComponents.choices
              choices={
                @current_round.question_data[:choices] || @current_round.question_data["choices"] ||
                  []
              }
              reveal={@reveal}
              round_closed?={@round_closed?}
              answered?={@answered?}
            />
          </div>
        </div>

        <div class="card bg-base-100">
          <div class="card-body">
            <h4 class="font-semibold">Scoreboard</h4>
            <div :if={@current_user == nil} class="text-sm opacity-70">
              Sign in to play and see your score.
            </div>
            <QuizComponents.scoreboard
              :if={@current_user != nil}
              entries={@scoreboard}
              nicknames={@nicknames}
            />
          </div>
        </div>
      </div>

      <div :if={!@current_round && @room.state == :lobby} class="alert alert-secondary">
        Waiting for host to start…
      </div>

      <div :if={@room.state == :ended} class="space-y-4">
        <div class="alert alert-info">
          Game Over. {if @host?, do: "You can start a new game."}
        </div>
        <div class="card bg-base-100">
          <div class="card-body">
            <h4 class="font-semibold">Final Scores</h4>
            <QuizComponents.scoreboard
              entries={@final_scoreboard || @scoreboard}
              nicknames={@nicknames}
            />
          </div>
        </div>
      </div>

      <% inter_rem =
        if @intermission_deadline_mono,
          do: ms_remaining(@intermission_deadline_mono, @now_mono) || 0,
          else: 0

      inter_total = @settings.intermission_ms || 1
      inter_val = if inter_total <= 0, do: 0, else: max(min(inter_total - inter_rem, inter_total), 0)
      overlay_pct = if inter_total <= 0, do: 0.0, else: inter_val * 100.0 / inter_total
      overlay_secs = round(Float.ceil(inter_rem / 1000.0))

      outcome =
        cond do
          # No reveal yet
          !@reveal ->
            nil

          # No one got it right (or time up): draw for everyone
          @reveal && @reveal.correct? == false ->
            :draw

          # Someone got it right; if this viewer picked the correct index, win, else lose
          true ->
            if @selected_index != nil and @selected_index == @reveal.correct_index,
              do: :win,
              else: :lose
        end %>
      <QuizComponents.result_overlay
        :if={@room.state != :ended and @round_closed?}
        outcome={outcome}
        seconds_left={overlay_secs}
        pct={overlay_pct}
        current_user={@current_user}
        intermission_rid={@intermission_rid}
        ready_user_ids={@ready_user_ids}
        presences={@presences}
        host?={@host?}
      />
    </Layouts.app>
    """
  end
end

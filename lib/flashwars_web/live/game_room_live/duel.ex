defmodule FlashwarsWeb.GameRoomLive.Duel do
  use FlashwarsWeb, :live_view

  alias Phoenix.PubSub
  require Ash.Query

  alias Flashwars.Games
  alias Flashwars.Games.{GameRoom, GameRound, GameSubmission}
  alias FlashwarsWeb.Presence

  @topic_prefix "flash_wars:room:"

  # Load user from session if present; allow anonymous viewing
  on_mount {FlashwarsWeb.LiveUserAuth, :current_user}
  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_optional}

  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(GameRoom, id, authorize?: false) do
      {:ok, room} ->
        if allowed_to_view?(room, socket.assigns.current_user) do
          setup_for_room(room, socket)
        else
          {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
        end

      _ ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def mount(%{"token" => token}, _session, socket) do
    room =
      GameRoom
      |> Ash.Query.for_read(:with_link_token, %{token: token})
      |> Ash.read!(authorize?: false)
      |> List.first()

    if room do
      setup_for_room(room, socket)
    else
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
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
    alias Flashwars.Org.OrgMembership

    OrgMembership
    |> Ash.Query.filter(organization_id == ^org_id and user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> case do
      [] -> false
      _ -> true
    end
  end

  defp setup_for_room(room, socket) do
    topic = topic(room.id)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Flashwars.PubSub, topic)

    # Load latest round without auth to support link-only guests from other orgs
    current_round =
      Flashwars.Games.GameRound
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.Query.sort(number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
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

  defp maybe_track_presence(socket, topic) do
    pres_avail? = presence_available?()

    # Existing presences (before tracking current socket) for uniqueness
    presences = if pres_avail?, do: presence_list_safe(topic), else: %{}

    used_names =
      presences
      |> Map.values()
      |> Enum.flat_map(fn %{metas: metas} -> Enum.map(metas, & &1[:name]) end)
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    {my_name, nicknames} =
      case socket.assigns.current_user do
        nil ->
          {nil, %{}}

        %{id: uid} ->
          # Prefer existing nickname if any, otherwise generate playful unique name
          existing = socket.assigns[:nicknames] && socket.assigns.nicknames[uid]
          base = existing || generate_playful_name(used_names)
          name = ensure_unique_name(base, used_names)
          {name, %{uid => name}}
      end

    if connected?(socket) and pres_avail? do
      key = presence_key(socket.assigns.current_user)
      meta = %{name: my_name || display_name(socket.assigns.current_user)}
      _ = Presence.track(self(), topic, key, meta)
    end

    # Refresh presences after potential tracking
    presences = if pres_avail?, do: presence_list_safe(topic), else: %{}

    socket
    |> assign(:presences, presences)
    |> assign(:ready_user_ids, MapSet.new())
    |> assign(:intermission_rid, nil)
    |> assign(:my_name, my_name)
    |> assign(:nicknames, Map.merge(socket.assigns.nicknames, nicknames))
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

  defp presence_key(nil),
    do: "anon:" <> Base.url_encode64(:crypto.strong_rand_bytes(4), padding: false)

  defp presence_key(%{id: uid}), do: to_string(uid)

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

  def handle_event("set_name", %{"name" => name}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :info, "Sign in to set name")}

      %{id: uid} ->
        trimmed = String.trim(name || "")
        valid? = String.length(trimmed) >= 1 and String.length(trimmed) <= 24

        if valid? do
          PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
            event: :name_set,
            user_id: uid,
            name: trimmed
          })

          # Update presence metadata
          _ =
            if presence_available?() and socket.assigns.current_user do
              Presence.update(
                self(),
                socket.assigns.topic,
                to_string(socket.assigns.current_user.id),
                fn _ -> %{name: trimmed} end
              )
            end

          {:noreply,
           socket
           |> assign(:my_name, trimmed)
           |> assign(:nicknames, Map.put(socket.assigns.nicknames, uid, trimmed))}
        else
          {:noreply, put_flash(socket, :error, "Name must be 1-24 characters")}
        end
    end
  end

  def handle_event("answer", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case {socket.assigns.current_user, socket.assigns.current_round} do
      {nil, _} ->
        {:noreply, put_flash(socket, :info, "Sign in to play")}

      {_, nil} ->
        {:noreply, socket}

      {%{id: _} = actor, round} ->
        # If this client already knows the round is closed, ignore
        if socket.assigns.round_closed? do
          {:noreply, socket}
        else
          qd = round.question_data || %{}
          answer_index = qd[:answer_index] || qd["answer_index"] || 0
          choices = qd[:choices] || qd["choices"] || []
          selected = Enum.at(choices, idx)
          correct? = idx == answer_index

          # Has someone already answered correctly? (authorize?: false for internal logic)
          already_won? =
            GameSubmission
            |> Ash.Query.filter(game_round_id == ^round.id and correct == true)
            |> Ash.Query.limit(1)
            |> Ash.read!(authorize?: false)
            |> case do
              [] -> false
              _ -> true
            end

          score = if correct? and not already_won?, do: 2, else: 0

          # Create submission (org + room are backfilled via changeset)
          _res =
            Games.submit(
              %{
                game_round_id: round.id,
                answer: selected,
                correct: correct?,
                score: score,
                submitted_at: DateTime.utc_now()
              },
              actor: actor
            )

          # Close the round on the first submission, reveal to everyone
          PubSub.broadcast(Flashwars.PubSub, socket.assigns.topic, %{
            event: :round_closed,
            round_id: round.id,
            user_id: actor.id,
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

  # Host reacts to round close to reveal and schedule next
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
      %{id: ^rid} = _round ->
        # Reveal immediately for host; schedule next round after intermission
        im = intermission_ms(socket.assigns.settings)
        Process.send_after(self(), {:next_round, rid}, im)

        {:noreply,
         socket
         |> assign(:round_closed?, true)
         |> assign(
           :answered?,
           socket.assigns.current_user && socket.assigns.current_user.id == uid
         )
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
         |> assign(:now_mono, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  # Guests react to round close: lock and reveal
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
      %{id: ^rid} ->
        {:noreply,
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
         |> start_intermission_timer(intermission_ms(socket.assigns.settings))
         |> assign(:round_deadline_mono, nil)
         |> assign(
           :intermission_deadline_mono,
           System.monotonic_time(:millisecond) + intermission_ms(socket.assigns.settings)
         )
         |> assign(:now_mono, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  # Everyone updates when a player sets their name
  def handle_info(%{event: :name_set, user_id: uid, name: name}, socket) do
    {:noreply,
     socket
     |> assign(:nicknames, Map.put(socket.assigns.nicknames, uid, name))}
  end

  # Presence diff
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, presence_list_safe(socket.assigns.topic))}
  end

  # Ready flow
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

  defp threshold_met?(socket) do
    present = map_size(socket.assigns.presences)
    ready = MapSet.size(socket.assigns.ready_user_ids)
    needed = max(1, trunc(Float.ceil(present * 0.6)))
    present > 0 and ready >= needed
  end

  # All clients update on new rounds
  def handle_info(%{event: :new_round, round: round}, socket) do
    {:noreply,
     socket
     |> assign(:current_round, round)
     |> assign(:answered?, false)
     |> assign(:round_closed?, false)
     |> assign(:selected_index, nil)
     |> assign(:reveal, nil)
     |> assign(:intermission_deadline_mono, nil)
     |> assign(:intermission_rid, nil)
     |> assign(:ready_user_ids, MapSet.new())
     |> setup_round_timer()
     |> assign(:scoreboard, fetch_scoreboard(socket.assigns.room, socket.assigns.current_user))}
  end

  # Host timeout: no answers until time up, close round
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

  # Host schedules next round generation after reveal delay
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

  # Everyone updates when the game ends
  def handle_info(%{event: :game_over}, socket) do
    {:noreply,
     assign(socket, :room, %{socket.assigns.room | state: :ended, ended_at: DateTime.utc_now()})}
  end

  # Tick for countdown display
  def handle_info(:tick, %{assigns: %{round_deadline_mono: nil}} = socket), do: {:noreply, socket}

  def handle_info(:tick, socket) do
    # Keep ticking while deadline set
    Process.send_after(self(), :tick, 1000)
    {:noreply, assign(socket, :now_mono, System.monotonic_time(:millisecond))}
  end

  # Separate tick for intermission countdown
  def handle_info(:intermission_tick, %{assigns: %{intermission_deadline_mono: nil}} = socket),
    do: {:noreply, socket}

  def handle_info(:intermission_tick, socket) do
    Process.send_after(self(), :intermission_tick, 1000)
    {:noreply, assign(socket, :now_mono, System.monotonic_time(:millisecond))}
  end

  # Ignore unknown messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp topic(id), do: @topic_prefix <> to_string(id)

  defp fetch_scoreboard(_room, nil), do: []

  defp fetch_scoreboard(room, actor) do
    subs =
      GameSubmission
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.read!(actor: actor)
      |> Ash.load!([:user], actor: actor)

    subs
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, subs} ->
      total = Enum.reduce(subs, 0, fn s, acc -> acc + (s.score || 0) end)
      user = subs |> List.first() |> Map.get(:user)
      %{user_id: user_id, user: user, name: display_name(user), score: total}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    actor = socket.assigns.current_user
    {config, privacy} = parse_settings(params)

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

  defp settings_from_room(%{config: cfg} = room) do
    %{
      rounds: (cfg && (cfg["rounds"] || cfg[:rounds])) || 10,
      types: (cfg && (cfg["types"] || cfg[:types])) || ["multiple_choice"],
      time_limit_ms: (cfg && (cfg["time_limit_ms"] || cfg[:time_limit_ms])) || nil,
      intermission_ms: (cfg && (cfg["intermission_ms"] || cfg[:intermission_ms])) || 10_000,
      privacy: room.privacy
    }
  end

  defp parse_settings(params) do
    rounds = parse_int(params["rounds"]) || 10
    types = params["types"] || []
    time_limit_ms = parse_int(params["time_limit_ms"]) || nil
    intermission_ms = parse_int(params["intermission_ms"]) || nil
    privacy = parse_privacy(params["privacy"]) || :private

    config = %{rounds: rounds, types: types, time_limit_ms: time_limit_ms}

    config =
      if intermission_ms, do: Map.put(config, :intermission_ms, intermission_ms), else: config

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

  defp invitation_link(room), do: ~p"/games/t/#{room.link_token}"

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

  defp name_for(assigns, nil), do: "Player"

  defp name_for(assigns, uid) do
    Map.get(assigns.nicknames, uid) ||
      Enum.find_value(assigns.scoreboard, fn e -> e.user_id == uid && e.name end) ||
      "Player"
  end

  @adjectives ~w(Brisk Clever Zippy Sly Jolly Witty Sunny Swift Cosmic Daring Jazzy Lively Quirky Rapid Snazzy)
  @animals ~w(Panda Falcon Tiger Koala Otter Fox Dolphin Llama Badger Eagle Gecko Panda Yak Corgi Puma)

  defp generate_playful_name(used_names) do
    # Generate until not in used set, then ensure uniqueness with suffix
    base =
      Enum.random(@adjectives) <> " " <> Enum.random(@animals)

    ensure_unique_name(base, used_names)
  end

  defp ensure_unique_name(base, used_names) do
    if MapSet.member?(used_names, base) do
      # try with numeric suffixes
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
          <button :if={@host? && @room.state == :ended} class="btn" phx-click="restart">
            Start New Game
          </button>
        </:actions>
      </.header>

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
                value={Atom.to_string(@settings.privacy)}
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

            <div :if={@settings.privacy == :link_only} class="mt-4">
              <label class="block text-sm font-medium">Copy Invitation Link</label>
              <div class="flex gap-2 items-center mt-2">
                <input class="input flex-1" type="text" readonly value={invitation_link(@room)} />
                <button
                  id="copy-invite"
                  type="button"
                  class="btn"
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
          <.form for={%{}} as={:name} id="duel-name-form" phx-submit="set_name">
            <div class="flex gap-2">
              <input
                class="input input-bordered flex-1"
                name="name"
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
          <ul>
            <%= for {key, %{metas: metas}} <- @presences do %>
              <li class="flex items-center gap-2 py-1">
                <span class="badge badge-success"></span>
                <span>{List.first(metas)[:name] || String.slice(key, 0, 6)}</span>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <div :if={@current_round && @room.state != :ended} id="duel-round" class="space-y-4">
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="text-sm opacity-70">
              Question {@current_round.number} of {@settings.rounds}
            </div>
            <div :if={@round_deadline_mono} class="text-sm space-y-1">
              <div>
                Time left: {round(
                  Float.ceil((ms_remaining(@round_deadline_mono, @now_mono) || 0) / 1000.0)
                )}s
              </div>
              <progress
                class="progress progress-primary w-full"
                value={
                  rem = ms_remaining(@round_deadline_mono, @now_mono) || 0
                  total = @settings.time_limit_ms || 1
                  if total <= 0, do: 0, else: max(min(total - rem, total), 0)
                }
                max={@settings.time_limit_ms || 1}
              >
              </progress>
            </div>
            <h3 class="text-xl font-semibold">
              {@current_round.question_data[:prompt] || @current_round.question_data["prompt"] || ""}
            </h3>

            <div class="mt-4 grid grid-cols-1 gap-2">
              <button
                :for={
                  {choice, idx} <-
                    Enum.with_index(
                      @current_round.question_data[:choices] ||
                        @current_round.question_data["choices"] || []
                    )
                }
                type="button"
                class={[
                  "btn",
                  @round_closed? && idx == (@reveal && @reveal.correct_index) && "btn-success",
                  @round_closed? && @reveal && idx == @reveal.selected_index &&
                    @reveal.selected_index != @reveal.correct_index && "btn-error"
                ]}
                phx-click="answer"
                phx-value-index={idx}
                disabled={@answered? || @round_closed?}
              >
                {choice}
              </button>
            </div>

            <div :if={@round_closed?} class="mt-4 space-y-2">
              <div class="alert">
                <span :if={@reveal && @reveal.user_id}>
                  {name_for(assigns, @reveal.user_id)} selected {Enum.at(
                    @current_round.question_data[:choices] || @current_round.question_data["choices"] ||
                      [],
                    @reveal.selected_index || -1
                  )}.
                </span>
                <span :if={@reveal && @reveal.user_id && @reveal.correct?} class="ml-1 text-success">
                  Correct!
                </span>
                <span :if={@reveal && @reveal.user_id && !@reveal.correct?} class="ml-1 text-error">
                  Incorrect.
                </span>
                <span class="ml-2">
                  Correct answer: {Enum.at(
                    @current_round.question_data[:choices] || @current_round.question_data["choices"] ||
                      [],
                    (@reveal && @reveal.correct_index) ||
                      (@current_round.question_data[:answer_index] ||
                         @current_round.question_data["answer_index"]) || -1
                  )}
                </span>
              </div>

              <div :if={@current_user} class="text-lg font-semibold">
                {case {@reveal && @reveal.correct?, @reveal && @reveal.user_id == @current_user.id} do
                  {true, true} -> "You won! 🏆"
                  {true, false} -> "You lose!"
                  {false, true} -> "You lose!"
                  {false, false} -> "You won!"
                end}
              </div>

              <div class="flex items-center gap-3">
                <div :if={@current_user && @intermission_rid}>
                  <button
                    :if={!MapSet.member?(@ready_user_ids, @current_user.id)}
                    class="btn btn-primary"
                    phx-click="ready"
                    phx-value-rid={@intermission_rid}
                  >
                    Ready
                  </button>
                  <button :if={MapSet.member?(@ready_user_ids, @current_user.id)} class="btn" disabled>
                    Ready ✔️
                  </button>
                </div>
                <div class="text-sm opacity-80">
                  Players ready: {MapSet.size(@ready_user_ids)} / {map_size(@presences)}
                </div>
                <button
                  :if={@host? && @intermission_rid}
                  class="btn"
                  phx-click="override_next"
                  phx-value-rid={@intermission_rid}
                >
                  Start Next Now
                </button>
              </div>

              <div :if={@intermission_deadline_mono} class="mt-2">
                <div class="text-sm">
                  Next round in {round(
                    Float.ceil((ms_remaining(@intermission_deadline_mono, @now_mono) || 0) / 1000.0)
                  )}s
                </div>
                <progress
                  class="progress w-full"
                  value={
                    rem = ms_remaining(@intermission_deadline_mono, @now_mono) || 0
                    total = @settings.intermission_ms || 1
                    if total <= 0, do: 0, else: max(min(total - rem, total), 0)
                  }
                  max={@settings.intermission_ms || 1}
                >
                </progress>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100">
          <div class="card-body">
            <h4 class="font-semibold">Scoreboard</h4>
            <div :if={@current_user == nil} class="text-sm opacity-70">
              Sign in to play and see your score.
            </div>
            <ul :if={@current_user != nil}>
              <li :for={entry <- @scoreboard} class="flex justify-between">
                <span>{Map.get(@nicknames, entry.user_id) || entry.name}</span>
                <span class="font-semibold">{entry.score}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div :if={!@current_round && @room.state == :lobby} class="alert">
        Waiting for host to start…
      </div>
      <div :if={@room.state == :ended} class="space-y-4">
        <div class="alert alert-info">Game Over. {if @host?, do: "You can start a new game."}</div>
        <div class="card bg-base-100">
          <div class="card-body">
            <h4 class="font-semibold">Final Scores</h4>
            <ul>
              <li :for={{entry, idx} <- Enum.with_index(@scoreboard, 1)} class="flex justify-between">
                <span>
                  {idx}. {Map.get(@nicknames, entry.user_id) || entry.name}
                  <span :if={idx == 1} class="badge badge-success ml-2">Winner</span>
                </span>
                <span class="font-semibold">{entry.score}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Restart flow: host only
  def handle_event("restart", _params, %{assigns: %{host?: true}} = socket) do
    actor = socket.assigns.current_user
    rid = socket.assigns.room.id

    # Delete submissions and rounds for this room (org constraints checked internally)
    Flashwars.Games.GameSubmission
    |> Ash.Query.filter(game_room_id == ^rid)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn s -> Ash.destroy!(s, authorize?: false) end)

    Flashwars.Games.GameRound
    |> Ash.Query.filter(game_room_id == ^rid)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn r -> Ash.destroy!(r, authorize?: false) end)

    {:ok, room} = Games.advance_state(socket.assigns.room, :lobby, actor: actor)

    {:noreply,
     socket
     |> assign(:room, room)
     |> assign(:current_round, nil)
     |> assign(:answered?, false)
     |> assign(:round_closed?, false)
     |> assign(:selected_index, nil)
     |> assign(:reveal, nil)
     |> assign(:round_deadline_mono, nil)
     |> assign(:now_mono, nil)
     |> assign(:scoreboard, fetch_scoreboard(room, actor))}
  end

  def handle_event("restart", _params, socket), do: {:noreply, socket}
end

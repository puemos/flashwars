defmodule FlashwarsWeb.StudySetLive.Test do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  alias Flashwars.Games

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(%{"id" => set_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, set} <- Content.get_study_set_by_id(set_id, actor: actor) do
      # Group this test session under a single attempt
      now = DateTime.utc_now()
      attempt =
        Learning.create_attempt!(
          %{mode: :test, study_set_id: set.id, started_at: now},
          actor: actor
        )

      items =
        Engine.generate_test(actor, set.id,
          size: 8,
          types: [:multiple_choice, :true_false],
          smart: true
        )

      {:ok,
       socket
       |> assign(:page_title, "Test · #{set.name}")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:attempt_id, attempt.id)
        |> assign(:items, items)
        |> assign(:index, 0)
        |> assign(:score, 0)
        |> assign(:answered?, false)
        |> assign(:correct?, nil)
        |> assign(:show_settings?, false)
        |> assign(:test_settings, %{size: 8, smart: true, types: [:multiple_choice, :true_false], pair_count: 4})
        |> assign(:test_settings_form, to_form(%{}, as: :test_settings))}
    else
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("answer", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    item = current_item(socket)

    correct? = idx == item.answer_index
    answer_text = Enum.at(item.choices, idx)

    _ =
      if item[:term_id] do
        grade = if correct?, do: :good, else: :again

        {:ok, _} =
          Learning.review(socket.assigns.current_user, item.term_id, grade,
            answer: answer_text,
            queue_type: :review,
            attempt_id: socket.assigns[:attempt_id]
          )
      end

    # Update score locally
    new_score = socket.assigns.score + if(correct?, do: 10, else: 0)

    {:noreply,
     socket
     |> assign(:answered?, true)
     |> assign(:correct?, correct?)
     |> assign(:score, new_score)}
  end

  def handle_event("toggle_test_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings?, !socket.assigns.show_settings?)}
  end

  def handle_event("test_settings_change", %{"test_settings" => params}, socket) do
    ts = parse_test_settings(params, socket.assigns.test_settings)
    {:noreply, assign(socket, :test_settings, ts)}
  end

  def handle_event("apply_test_preset", %{"preset" => preset}, socket) do
    ts = socket.assigns.test_settings
    new =
      case preset do
        "quick" -> %{ts | size: 6, smart: true, types: [:multiple_choice, :true_false]}
        "mc_only" -> %{ts | size: ts.size, smart: false, types: [:multiple_choice]}
        "free_text" -> %{ts | size: 8, smart: false, types: [:free_text]}
        _ -> ts
      end
    {:noreply, assign(socket, :test_settings, new)}
  end

  def handle_event("restart_test", _params, socket) do
    actor = socket.assigns.current_user
    set = socket.assigns.study_set
    ts = socket.assigns.test_settings

    items = Engine.generate_test(actor, set.id,
      size: ts.size,
      types: ts.types,
      pair_count: ts.pair_count,
      smart: ts.smart
    )

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:index, 0)
     |> assign(:score, 0)
     |> assign(:answered?, false)
     |> assign(:correct?, nil)
     |> put_flash(:info, "New test generated")}
  end

  def handle_event("next", _params, socket) do
    new_index = socket.assigns.index + 1

    # Advance to next question

    {:noreply,
     socket
     |> assign(:index, new_index)
     |> assign(:answered?, false)
     |> assign(:correct?, nil)}
  end

  def handle_event("create_duel", _params, socket) do
    actor = socket.assigns.current_user
    set = socket.assigns.study_set

    case Games.create_game_room(%{type: :duel, study_set_id: set.id, privacy: :private},
           actor: actor
         ) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/games/r/#{room.id}")}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Could not create duel: #{inspect(err)}")}
    end
  end

  defp current_item(socket) do
    Enum.at(socket.assigns.items, socket.assigns.index)
  end

  # Minimal session state persisted via default_state(:test)

  defp parse_test_settings(params, current) do
    types_map = Map.get(params, "types", %{})

    selected =
      [:multiple_choice, :true_false, :free_text, :matching]
      |> Enum.filter(fn t -> Map.get(types_map, Atom.to_string(t)) in ["true", "on", true] end)

    size = parse_int(Map.get(params, "size"), current.size)
    pair_count = parse_int(Map.get(params, "pair_count"), current.pair_count)
    smart = Map.get(params, "smart") in ["true", "on", true]

    types = if selected == [], do: current.types, else: selected

    %{current | size: size, pair_count: pair_count, smart: smart, types: types}
  end

  defp parse_int(nil, fallback), do: fallback
  defp parse_int(<<>>, fallback), do: fallback
  defp parse_int(val, fallback) when is_binary(val) do
    case Integer.parse(val) do
      {i, ""} when i > 0 -> i
      _ -> fallback
    end
  end
  defp parse_int(val, _fallback) when is_integer(val), do: val

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Test: {@study_set.name}
        <:subtitle>Answer mixed questions</:subtitle>
        <:actions>
          <.button phx-click="toggle_test_settings" class="btn btn-sm">Settings</.button>
          <.button phx-click="create_duel" variant="primary">Create Duel</.button>
        </:actions>
      </.header>

      <!-- Test Settings -->
      <div :if={@show_settings?} class="card bg-base-200 mb-4">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h3 class="card-title">Test Settings</h3>
            <div class="flex gap-2">
              <button class="btn btn-xs" phx-click="apply_test_preset" phx-value-preset="quick">Quick</button>
              <button class="btn btn-xs" phx-click="apply_test_preset" phx-value-preset="mc_only">MC Only</button>
              <button class="btn btn-xs" phx-click="apply_test_preset" phx-value-preset="free_text">Free Text</button>
            </div>
          </div>
          <.form for={@test_settings_form} id="test-settings-form" phx-change="test_settings_change">
            <div class="grid grid-cols-1 md:grid-cols-5 gap-4 items-end">
              <div>
                <.input type="number" field={@test_settings_form[:size]} label="Questions" value={@test_settings.size} min="3" max="50" />
                <div class="text-xs opacity-70">How many questions in the test</div>
              </div>
              <div>
                <.input type="number" field={@test_settings_form[:pair_count]} label="Matching pairs" value={@test_settings.pair_count} min="2" max="10" />
                <div class="text-xs opacity-70">Only used for Matching</div>
              </div>
              <div class="md:col-span-3">
                <div class="flex items-center gap-2">
                  <input type="checkbox" name="test_settings[smart]" id="test-smart" checked={@test_settings.smart} class="checkbox checkbox-sm" />
                  <label for="test-smart" class="text-sm">Smart selection (balanced mix)</label>
                </div>
                <div class="mt-3">
                  <label class="block text-sm font-medium mb-1">Question Types</label>
                  <div class="flex flex-wrap gap-3">
                    <label class="badge gap-2 cursor-pointer select-none">
                      <input type="checkbox" name="test_settings[types][multiple_choice]" checked={Enum.member?(@test_settings.types, :multiple_choice)} class="checkbox checkbox-xs" />
                      <span>Multiple choice</span>
                    </label>
                    <label class="badge gap-2 cursor-pointer select-none">
                      <input type="checkbox" name="test_settings[types][true_false]" checked={Enum.member?(@test_settings.types, :true_false)} class="checkbox checkbox-xs" />
                      <span>True/False</span>
                    </label>
                    <label class="badge gap-2 cursor-pointer select-none">
                      <input type="checkbox" name="test_settings[types][free_text]" checked={Enum.member?(@test_settings.types, :free_text)} class="checkbox checkbox-xs" />
                      <span>Free text</span>
                    </label>
                    <label class="badge gap-2 cursor-pointer select-none">
                      <input type="checkbox" name="test_settings[types][matching]" checked={Enum.member?(@test_settings.types, :matching)} class="checkbox checkbox-xs" />
                      <span>Matching</span>
                    </label>
                  </div>
                </div>
              </div>
            </div>
          </.form>
          <div class="mt-3 flex items-center justify-between">
            <div class="text-xs opacity-70">Tip: Use presets for a quick start, then tweak as needed</div>
            <.button phx-click="restart_test" class="btn btn-sm">Start New Test With Settings</.button>
          </div>
        </div>
      </div>

      <div class="flex items-center justify-between mb-2">
        <div class="badge">Score: {@score}</div>
        <div class="text-sm opacity-70">
          Q {@index + 1} / {length(@items)}
        </div>
      </div>

      <%= if @index >= length(@items) do %>
        <div class="card bg-base-200">
          <div class="card-body items-center">
            <h3 class="card-title">Test Complete</h3>
            <p>Final Score: {@score}</p>
          </div>
        </div>
      <% else %>
        <% item = Enum.at(@items, @index) %>
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="text-sm opacity-70">Question</div>
            <h3 class="text-xl font-semibold">{item.prompt}</h3>

            <div class="mt-4 grid grid-cols-1 gap-2">
              <button
                :for={{choice, idx} <- Enum.with_index(item.choices)}
                type="button"
                class="btn"
                data-choice-index={idx}
                phx-click="answer"
                phx-value-index={idx}
                disabled={@answered?}
              >
                {choice}
              </button>
            </div>

            <div :if={@answered?} class="mt-4">
              <div :if={@correct?} class="alert alert-success">Correct!</div>
              <div :if={!@correct?} class="alert alert-error">
                Incorrect. Answer: {Enum.at(item.choices, item.answer_index)}
              </div>
              <button class="btn btn-primary mt-3" phx-click="next">Next</button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end

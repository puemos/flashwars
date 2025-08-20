defmodule FlashwarsWeb.StudySetLive.Show do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Content.{StudySet, Term}
  alias Flashwars.Learning
  alias Flashwars.Games
  import Phoenix.Component

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_admin}

  def mount(%{"id" => id}, _session, socket) do
    with {:ok, set} <- Content.get_study_set_by_id(id, actor: socket.assigns.current_user),
         {:ok, terms} <- read_terms(set, socket.assigns.current_user) do
      form = to_form(%{"term" => "", "definition" => ""}, as: :term)
      bulk_form = to_form(%{"csv" => ""}, as: :bulk)
      mastery_map = mastery_map(socket.assigns.current_user, set.id)

      {:ok,
       socket
       |> assign(:page_title, "Add Terms")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:form, form)
       |> assign(:bulk_form, bulk_form)
       # editing state
       |> assign(:editing_id, nil)
       |> assign(:edit_form, nil)
       |> assign(:mastery_map, mastery_map)
       |> assign(:next_position, length(terms) + 1)
       |> stream(:terms, terms)}
    else
      _ ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("add", %{"term" => params}, socket) do
    params =
      params
      |> Map.put_new("study_set_id", socket.assigns.study_set.id)
      |> Map.put_new("position", socket.assigns.next_position)

    case Content.create_term(params, actor: socket.assigns.current_user) do
      {:ok, term} ->
        {:noreply,
         socket
         |> stream_insert(:terms, term)
         |> assign(:next_position, socket.assigns.next_position + 1)
         |> assign(:form, to_form(%{"term" => "", "definition" => ""}, as: :term))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add term")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Ash.get(Term, id, actor: socket.assigns.current_user) do
      {:ok, term} ->
        edit_form = to_form(%{"term" => term.term, "definition" => term.definition}, as: :edit)
        {:noreply, socket |> assign(:editing_id, id) |> assign(:edit_form, edit_form)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_id, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("save_edit", %{"edit" => params, "_row_id" => id}, socket) do
    with {:ok, term} <- Ash.get(Term, id, actor: socket.assigns.current_user),
         {:ok, _updated} <-
           term
           |> Ash.Changeset.for_update(
             :update,
             %{term: params["term"], definition: params["definition"]},
             actor: socket.assigns.current_user
           )
           |> Ash.update(),
         {:ok, refreshed} <- read_terms(socket.assigns.study_set, socket.assigns.current_user) do
      {:noreply,
       socket
       |> stream(:terms, refreshed, reset: true)
       |> assign(:editing_id, nil)
       |> assign(:edit_form, nil)
       |> put_flash(:info, "Updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update term")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, term} <- Ash.get(Term, id, actor: socket.assigns.current_user),
         {:ok, _} <- Ash.destroy(term, actor: socket.assigns.current_user),
         {:ok, refreshed} <- read_terms(socket.assigns.study_set, socket.assigns.current_user) do
      {:noreply,
       socket
       |> stream(:terms, refreshed, reset: true)
       |> assign(:next_position, max(socket.assigns.next_position - 1, 1))
       |> put_flash(:info, "Deleted")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete term")}
    end
  end

  def handle_event("bulk_add", %{"bulk" => %{"csv" => csv}}, socket) do
    lines = csv |> String.split(["\n", "\r"], trim: true)

    {created, _errors} =
      Enum.reduce(lines, {[], []}, fn line, {acc, errs} ->
        case parse_csv_line(line) do
          {t0, d0} ->
            t = String.trim(t0 || "")
            d = String.trim(d0 || "")

            if t != "" and d != "" do
              params = %{
                "term" => String.trim(t),
                "definition" => String.trim(d),
                "study_set_id" => socket.assigns.study_set.id,
                "position" => socket.assigns.next_position + length(acc)
              }

              case Content.create_term(params, actor: socket.assigns.current_user) do
                {:ok, term} -> {[term | acc], errs}
                {:error, e} -> {acc, [e | errs]}
              end
            else
              {acc, errs}
            end
        end
      end)

    terms = Enum.reverse(created)

    {:noreply,
     socket
     |> stream(:terms, terms)
     |> assign(:next_position, socket.assigns.next_position + length(terms))
     |> assign(:bulk_form, to_form(%{"csv" => ""}, as: :bulk))
     |> put_flash(:info, "Added #{length(terms)} terms")}
  end

  def handle_event("refresh_mastery", _params, socket) do
    mm = mastery_map(socket.assigns.current_user, socket.assigns.study_set.id)
    {:noreply, assign(socket, :mastery_map, mm)}
  end

  def handle_event("save_privacy", %{"set" => %{"privacy" => priv}}, socket) do
    with {:ok, set} <-
           Ash.get(StudySet, socket.assigns.study_set.id, actor: socket.assigns.current_user),
         {:ok, updated} <-
           set
           |> Ash.Changeset.for_update(:update, %{privacy: String.to_existing_atom(priv)},
             actor: socket.assigns.current_user
           )
           |> Ash.update() do
      {:noreply, socket |> assign(:study_set, updated) |> put_flash(:info, "Settings saved")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not save settings")}
    end
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

  defp read_terms(%StudySet{id: id}, actor) do
    Term
    |> Ash.Query.for_read(:for_study_set, %{study_set_id: id})
    |> Ash.read(actor: actor)
  end

  defp mastery_map(nil, _set_id), do: %{}
  defp mastery_map(_user, nil), do: %{}

  defp mastery_map(user, set_id) do
    res = Learning.mastery_for_set(user, set_id)

    %{}
    |> Map.merge(Map.new(res.mastered, &{&1.term_id, :mastered}))
    |> Map.merge(Map.new(res.struggling, &{&1.term_id, :struggling}))
    |> Map.merge(Map.new(res.practicing, &{&1.term_id, :practicing}))
    |> Map.merge(Map.new(res.unseen, &{&1.term_id, :unseen}))
  end

  defp parse_csv_line(line) do
    # very light CSV: first comma splits term,definition; supports quoted fields
    trimmed = String.trim(line)

    case Regex.run(~r/^\s*\"?([^\"]*)\"?\s*,\s*\"?(.+?)\"?\s*$/, trimmed) do
      [_, term, defn] ->
        {term, defn}

      _ ->
        case String.split(trimmed, ",", parts: 2) do
          [t, d] -> {t, d}
          _ -> {"", ""}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Build Set: {@study_set.name}
        <:subtitle>Manage terms, sharing, and expertise</:subtitle>
        <:actions>
          <div class="flex gap-2">
            <button class="btn btn-primary" phx-click="create_duel">Create Duel</button>
            <.link navigate={~p"/"} class="btn">Done</.link>
          </div>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-1 space-y-6">
          <div class="card bg-base-200">
            <div class="card-body">
              <h4 class="font-semibold">Share Settings</h4>
              <.form for={to_form(%{}, as: :set)} id="set-privacy-form" phx-submit="save_privacy">
                <.input
                  name="set[privacy]"
                  type="select"
                  label="Privacy"
                  value={Atom.to_string(@study_set.privacy)}
                  options={[{"Private", "private"}, {"Link only", "link_only"}, {"Public", "public"}]}
                />
                <div :if={@study_set.privacy == :link_only} class="mt-2">
                  <label class="block text-sm font-medium">Link</label>
                  <% share_link =
                    FlashwarsWeb.Endpoint.url() <> "/s/t/" <> to_string(@study_set.link_token || "") %>
                  <div class="flex gap-2 items-center">
                    <input class="input flex-1" readonly value={share_link} />
                    <button
                      type="button"
                      class="btn btn-secondary"
                      id="copy-set-link"
                      phx-hook="CopyToClipboard"
                      data-text={share_link}
                    >
                      Copy
                    </button>
                  </div>
                </div>
                <div class="flex justify-end mt-3">
                  <.button class="btn btn-primary">Save</.button>
                </div>
              </.form>
            </div>
          </div>
          <div class="card bg-base-200">
            <div class="card-body">
              <h4 class="font-semibold">Add Single</h4>
              <.form for={@form} id="term-form" phx-submit="add">
                <.input field={@form[:term]} type="text" label="Term" required />
                <.input field={@form[:definition]} type="textarea" label="Definition" required />
                <div class="flex justify-end">
                  <.button class="btn btn-primary">Add</.button>
                </div>
              </.form>
              <p class="text-xs opacity-70 mt-2">Next position: {@next_position}</p>
            </div>
          </div>
          <div class="card bg-base-200">
            <div class="card-body">
              <h4 class="font-semibold">Bulk Add (CSV)</h4>
              <p class="text-xs opacity-70">One per line, format: term,definition</p>
              <.form for={@bulk_form} id="bulk-form" phx-submit="bulk_add">
                <.input field={@bulk_form[:csv]} type="textarea" class="min-h-32" />
                <div class="flex justify-end">
                  <.button class="btn btn-secondary">Add CSV</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>
        <div class="lg:col-span-2">
          <div id="terms" class="card bg-base-200">
            <div class="card-body">
              <div class="flex items-center justify-between mb-2">
                <h4 class="font-semibold">Terms</h4>
                <button class="btn btn-ghost btn-sm" phx-click="refresh_mastery">
                  Refresh Expertise
                </button>
              </div>
              <.table id="terms-table" rows={@streams.terms} row_id={fn {id, _t} -> id end}>
                <:col :let={{_id, t}} label="Term">
                  <div :if={@editing_id != t.id}>{t.term}</div>
                  <.input :if={@editing_id == t.id} field={@edit_form[:term]} type="text" />
                </:col>
                <:col :let={{_id, t}} label="Definition">
                  <div :if={@editing_id != t.id}>{t.definition}</div>
                  <.input :if={@editing_id == t.id} field={@edit_form[:definition]} type="textarea" />
                </:col>
                <:col :let={{_id, t}} label="Expertise">
                  <% status = @mastery_map[t.id] %>
                  <span :if={status == :mastered} class="badge badge-success">Mastered</span>
                  <span :if={status == :struggling} class="badge badge-error">Struggling</span>
                  <span :if={status == :practicing} class="badge badge-warning">Practicing</span>
                  <span :if={status == :unseen or status == nil} class="badge">Unseen</span>
                </:col>
                <:col :let={{_id, t}} label="Actions">
                  <div :if={@editing_id != t.id} class="flex gap-2">
                    <button class="btn btn-sm" phx-click="edit" phx-value-id={t.id}>Edit</button>
                    <button class="btn btn-sm btn-error" phx-click="delete" phx-value-id={t.id}>
                      Delete
                    </button>
                  </div>
                  <div :if={@editing_id == t.id} class="flex gap-2">
                    <.form for={@edit_form} id={"edit-form-#{t.id}"} phx-submit="save_edit">
                      <input type="hidden" name="_row_id" value={t.id} />
                      <button class="btn btn-sm btn-primary">Save</button>
                    </.form>
                    <button class="btn btn-sm" phx-click="cancel_edit">Cancel</button>
                  </div>
                </:col>
              </.table>
              <div :if={Enum.empty?(@streams.terms.inserts)} class="text-sm opacity-70">
                No terms yet. Add your first one on the left.
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

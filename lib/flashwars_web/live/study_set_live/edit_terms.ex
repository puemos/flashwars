defmodule FlashwarsWeb.StudySetLive.EditTerms do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Content.{StudySet, Term}
  import Phoenix.Component

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_admin}

  def mount(%{"id" => id}, _session, socket) do
    with {:ok, set} <- Content.get_study_set_by_id(id, actor: socket.assigns.current_user),
         {:ok, terms} <- read_terms(set, socket.assigns.current_user) do
      form = to_form(%{"term" => "", "definition" => ""}, as: :term)

      {:ok,
       socket
       |> assign(:page_title, "Add Terms")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:form, form)
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

  defp read_terms(%StudySet{id: id}, actor) do
    Term
    |> Ash.Query.for_read(:for_study_set, %{study_set_id: id})
    |> Ash.read(actor: actor)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Add Terms
        <:subtitle>Set: {@study_set.name}</:subtitle>
        <:actions>
          <.link navigate={~p"/"} class="btn">Done</.link>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-1">
          <div class="card bg-base-200">
            <div class="card-body">
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
        </div>
        <div class="lg:col-span-2">
          <div id="terms" class="card bg-base-200">
            <div class="card-body">
              <.table id="terms-table" rows={@streams.terms} row_id={fn {id, _t} -> id end}>
                <:col :let={{_id, t}} label="#">{t.position}</:col>
                <:col :let={{_id, t}} label="Term">{t.term}</:col>
                <:col :let={{_id, t}} label="Definition">{t.definition}</:col>
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

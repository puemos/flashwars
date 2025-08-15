defmodule FlashwarsWeb.StudySetLive.New do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  import Phoenix.Component

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_admin}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Study Set")
     |> assign_new(:current_scope, fn -> nil end)
     |> assign(:form, to_form(%{"name" => "", "description" => "", "privacy" => "private"}, as: :study_set))}
  end

  def handle_event("validate", %{"study_set" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :study_set))}
  end

  def handle_event("save", %{"study_set" => params}, socket) do
    params = normalize_params(params)

    params = Map.put_new(params, "organization_id", socket.assigns.current_org.id)
    params = Map.put_new(params, "owner_id", socket.assigns.current_user.id)

    case Content.create_study_set(params, actor: socket.assigns.current_user) do
      {:ok, set} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/orgs/#{socket.assigns.current_org.id}/study_sets/#{set.id}/terms"
         )}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the errors below")
         |> assign(:form, to_form(params, as: :study_set))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not create study set")}
    end
  end

  defp normalize_params(params) do
    params
    |> Map.update("privacy", :private, fn
      val when is_binary(val) -> String.to_existing_atom(val)
      val -> val
    end)
  end

  # current_org is provided by on_mount

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        New Study Set
        <:subtitle>Create a study set, then add terms</:subtitle>
      </.header>

      <div class="card bg-base-200">
        <div class="card-body">
          <.form for={@form} id="new-study-set" phx-change="validate" phx-submit="save">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label="Name" required />
              <.input field={@form[:description]} type="text" label="Description" />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <.input
                field={@form[:privacy]}
                type="select"
                label="Privacy"
                options={[{"Private", "private"}, {"Link only", "link_only"}, {"Public", "public"}]}
              />
              <div class="sm:col-span-2 flex items-end justify-end">
                <.button class="btn btn-primary">
                  Create &amp; Add Terms
                </.button>
              </div>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

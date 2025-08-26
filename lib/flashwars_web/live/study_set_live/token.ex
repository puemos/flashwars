defmodule FlashwarsWeb.StudySetLive.Token do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content.{StudySet, Term}
  require Ash.Query

  # Allow anonymous visitors; user may or may not be present
  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    # Load the link-shared study set
    set =
      StudySet
      |> Ash.Query.for_read(:with_link_token, %{token: token})
      |> Ash.read_one!(authorize?: false)

    if is_nil(set) do
      {:halt,
       socket
       |> put_flash(:error, "Study set not found or not shared via link")
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    else
      # Load terms for this shared set via tokened read
      terms =
        Term
        |> Ash.Query.for_read(:with_link_token, %{token: token})
        |> Ash.read!(authorize?: false)

      {:ok,
       socket
       |> assign(:page_title, set.name)
       |> assign_new(:current_scope, fn -> %{} end)
       |> assign(:study_set, set)
       |> assign(:terms, terms)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        {@study_set.name}
        <:subtitle>Shared via link</:subtitle>
      </.header>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="overflow-x-auto">
            <table id="terms" class="table">
              <thead>
                <tr>
                  <th>Term</th>
                  <th>Definition</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @terms} id={"term-#{t.id}"}>
                  <td>{t.term}</td>
                  <td>{t.definition}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

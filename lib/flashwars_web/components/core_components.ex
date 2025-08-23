defmodule FlashwarsWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: FlashwarsWeb.Gettext

  # Routes generation with the ~p sigil
  use Phoenix.VerifiedRoutes,
    endpoint: FlashwarsWeb.Endpoint,
    router: FlashwarsWeb.Router,
    statics: FlashwarsWeb.static_paths()

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-bottom toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  # ——— Progress (overlay-style) ———
  attr :pct, :float, required: true
  attr :height, :string, default: "h-3"
  attr :rounded, :boolean, default: true
  attr :class, :any, default: nil

  def progress(assigns) do
    ~H"""
    <div
      class={["overlay-progress overflow-hidden", @rounded && "rounded-full", @height, @class]}
      style={"--pct: #{@pct}%"}
    >
      <div class="bar"></div>
    </div>
    """
  end

  # ——— Stat (label + value) ———
  attr :label, :string, required: true
  attr :value, :any, required: true
  # "left" | "center" | "right"
  attr :align, :string, default: "left"
  attr :class, :any, default: nil

  def stat(assigns) do
    align_class =
      case assigns.align do
        "center" -> "text-center"
        "right" -> "text-right"
        _ -> ""
      end

    assigns = assign(assigns, :align_class, align_class)

    ~H"""
    <div class={["text-sm opacity-90", @align_class, @class]}>
      <div class="uppercase text-xs">{@label}</div>
      <div class="font-extrabold tabular-nums">{@value}</div>
    </div>
    """
  end

  # ——— Sticky top wrapper ———
  slot :inner_block, required: true
  attr :class, :any, default: nil

  def sticky_top(assigns) do
    ~H"""
    <div class={["sticky top-0 z-30", @class]}>
      <div class="relative border-b border-base-300">
        <div class="relative mx-auto max-w-6xl px-4 py-3">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  # ——— Keyboard badge ———
  attr :text, :string, required: true
  attr :size, :string, default: "kbd kbd-lg"

  def kbd(assigns) do
    ~H"""
    <kbd class={[@size]}>{@text}</kbd>
    """
  end

  # ——— Rank badge (1..n) ———
  attr :index, :integer, required: true

  def rank_badge(assigns) do
    ~H"""
    <span class={[
      "badge",
      @index == 1 && "badge-warning",
      @index == 2 && "badge-info",
      @index == 3 && "badge-secondary",
      @index > 3 && "badge-ghost"
    ]}>
      {@index}
    </span>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders a study set card with mastery status.

  ## Examples

      <.study_set_card
        set={@set}
        current_org={@current_org}
        show_mastery={true}
      />
  """
  attr :set, :map, required: true, doc: "the study set to display"
  attr :current_org, :map, required: true, doc: "the current organization"
  attr :show_mastery, :boolean, default: true, doc: "whether to show mastery status"
  attr :show_actions, :boolean, default: true, doc: "whether to show action buttons"

  def study_set_card(assigns) do
    ~H"""
    <div class="hover:bg-base-300/20 px-2 -mx-2 rounded py-4 transition-all">
      <div class="grid grid-cols-[1fr_auto_auto] gap-6 items-start">
        <!-- Title and metadata section -->
        <div class="min-w-0 space-y-2">
          <div class="flex items-start justify-between gap-4">
            <.link
              navigate={~p"/orgs/#{@current_org.id}/study_sets/#{@set.id}"}
              class="font-semibold text-lg hover:underline transition-colors block leading-tight min-w-0"
            >
              {@set.name}
            </.link>
            <span
              :if={is_integer(@set.terms_count)}
              class="flex items-center gap-1 text-sm text-base-content/60 flex-shrink-0"
            >
              <.icon name="hero-rectangle-stack" class="size-3" />
              {@set.terms_count} terms
            </span>
          </div>
          
    <!-- Progress summary (moved from right side) -->
          <div
            :if={(@show_mastery and @set.mastery_status) && @set.mastery_status.total > 0}
            class="space-y-0.5"
          >
            <div class="text-sm font-medium text-base-content/60">
              {@set.mastery_status.percentage}% Complete
            </div>
          </div>
        </div>
        
    <!-- Progress section -->
        <div class="justify-self-end">
          <div
            :if={(@show_mastery and @set.mastery_status) && @set.mastery_status.total > 0}
            class="text-right space-y-3"
          >
            <!-- Progress bar -->
            <div class="flex justify-end">
              <div class="tooltip tooltip-bottom" data-tip={"#{@set.mastery_status.percentage}%"}>
                <div class="w-36 h-2 bg-base-300 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-gradient-to-r from-success to-success-content rounded-full transition-all duration-300"
                    style={"width: #{@set.mastery_status.percentage}%"}
                  >
                  </div>
                </div>
              </div>
            </div>
            
    <!-- Compact detailed breakdown with tooltips -->
            <div class="flex flex-wrap gap-3 justify-end">
              <!-- Mastered -->
              <div class="tooltip tooltip-bottom" data-tip="Mastered terms">
                <div class="flex items-center gap-1.5 text-xs cursor-help">
                  <div class="w-2 h-2 rounded-full bg-success"></div>
                  <span class="text-success font-medium">{@set.mastery_status.mastered}</span>
                </div>
              </div>
              
    <!-- Learning -->
              <div
                class="tooltip tooltip-bottom"
                data-tip="Terms being learned"
              >
                <div class="flex items-center gap-1.5 text-xs cursor-help">
                  <div class="w-2 h-2 rounded-full bg-warning"></div>
                  <span class="text-warning font-medium">{@set.mastery_status.practicing}</span>
                </div>
              </div>
              
    <!-- Struggling -->
              <div
                class="tooltip tooltip-bottom"
                data-tip="Terms you're struggling with"
              >
                <div class="flex items-center gap-1.5 text-xs cursor-help">
                  <div class="w-2 h-2 rounded-full bg-error"></div>
                  <span class="text-error font-medium">{@set.mastery_status.struggling}</span>
                </div>
              </div>
              
    <!-- New -->
              <div
                class="tooltip tooltip-bottom"
                data-tip="New terms not yet studied"
              >
                <div class="flex items-center gap-1.5 text-xs cursor-help">
                  <div class="w-2 h-2 rounded-full bg-info"></div>
                  <span class="text-info font-medium">{@set.mastery_status.unseen}</span>
                </div>
              </div>
            </div>
          </div>
          
    <!-- New set indicator -->
          <div
            :if={(@show_mastery and @set.mastery_status) && @set.mastery_status.total == 0}
            class="flex items-center gap-2 text-info bg-info/10 px-3 py-2 rounded-full"
          >
            <.icon name="hero-sparkles" class="size-4" />
            <span class="text-sm font-medium">New Set</span>
          </div>
        </div>
        
    <!-- Actions dropdown -->
        <div :if={@show_actions} class="dropdown dropdown-end justify-self-end">
          <div tabindex="0" role="button" class="btn btn-ghost btn-sm hover:bg-base-200">
            <.icon name="hero-ellipsis-horizontal" class="size-4" />
            <span class="sr-only">More actions</span>
          </div>
          <ul
            tabindex="0"
            class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-52 border border-base-300"
          >
            <li>
              <.link
                navigate={~p"/orgs/#{@current_org.id}/study_sets/#{@set.id}"}
                class="flex items-center gap-2"
              >
                <.icon name="hero-eye" class="size-4" /> View Set
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/orgs/#{@current_org.id}/study_sets/#{@set.id}/learn"}
                class="flex items-center gap-2"
              >
                <.icon name="hero-academic-cap" class="size-4" /> Start Studying
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(FlashwarsWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(FlashwarsWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

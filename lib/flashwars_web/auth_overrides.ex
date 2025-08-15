defmodule FlashwarsWeb.AuthOverrides do
  @moduledoc false
  use AshAuthentication.Phoenix.Overrides

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "grid h-screen place-items-center bg-base-100"
  end

  override AshAuthentication.Phoenix.ResetLive do
    set :root_class, "grid h-screen place-items-center bg-base-100"
  end

  override AshAuthentication.Phoenix.Components.Reset do
    set :root_class, """
    flex-1 flex flex-col justify-center py-12 px-4 sm:px-6 lg:flex-none
    lg:px-20 xl:px-24
    """

    set :strategy_class, "mx-auto w-full max-w-sm lg:w-96"
  end

  override AshAuthentication.Phoenix.Components.Reset.Form do
    set :root_class, nil
    set :label_class, "mt-2 mb-4 text-2xl tracking-tight font-bold text-base-content"
    set :form_class, nil
    set :spacer_class, "py-1"
    set :disable_button_text, "Changing password ..."
  end

  override AshAuthentication.Phoenix.Components.SignIn do
    set :root_class, """
    flex-1 flex flex-col justify-center py-12 px-4 sm:px-6 lg:flex-none
    lg:px-20 xl:px-24 border rounded-md border-base-300 bg-base-200/30
    """

    set :show_banner, false
    set :strategy_class, "mx-auto w-full max-w-sm lg:w-96"

    set :authentication_error_container_class, "text-base-content text-center"
    set :authentication_error_text_class, ""
  end

  override AshAuthentication.Phoenix.Components.Banner do
    set :root_class, "w-full flex justify-center py-2"
    set :href_class, nil
    set :href_url, "/"
    set :image_class, "block"
    set :dark_image_class, "hidden"
    set :image_url, "https://ash-hq.org/images/ash-framework-light.png"
    set :dark_image_url, "https://ash-hq.org/images/ash-framework-dark.png"
    set :text_class, nil
    set :text, nil
  end

  override AshAuthentication.Phoenix.Components.HorizontalRule do
    set :root_class, "relative my-2"
    set :hr_outer_class, "absolute inset-0 flex items-center"
    set :hr_inner_class, "w-full border-t border-base-300"
    set :text_outer_class, "relative flex justify-center text-sm"
    set :text_inner_class, "px-2 bg-base-100 text-base-content font-medium"
    set :text, "or"
  end

  override AshAuthentication.Phoenix.Components.MagicLink do
    set :root_class, "mt-4 mb-4"
    set :label_class, "mt-2 mb-4 text-2xl tracking-tight font-bold text-base-content"
    set :form_class, nil

    set :request_flash_text,
        "If this user exists in our database you will contacted with a sign-in link shortly."

    set :disable_button_text, "Requesting ..."
  end

  override AshAuthentication.Phoenix.Components.Password do
    set :root_class, "mt-4 mb-4"
    set :interstitial_class, "flex flex-row justify-between content-between text-sm font-medium"

    set :toggler_class,
        "flex-none text-base-content/70 hover:text-base-content px-2 first:pl-0 last:pr-0"

    set :sign_in_toggle_text, "Already have an account?"
    set :register_toggle_text, "Need an account?"
    set :reset_toggle_text, "Forgot your password?"
    set :show_first, :sign_in
    set :hide_class, "hidden"
  end

  override AshAuthentication.Phoenix.Components.Password.SignInForm do
    set :root_class, nil
    set :label_class, "mt-2 mb-4 text-2xl tracking-tight font-bold text-base-content"
    set :form_class, nil
    set :slot_class, "my-4"
    set :disable_button_text, "Signing in ..."
  end

  override AshAuthentication.Phoenix.Components.Password.RegisterForm do
    set :root_class, nil
    set :label_class, "mt-2 mb-4 text-2xl tracking-tight font-bold text-base-content"
    set :form_class, nil
    set :slot_class, "my-4"
    set :disable_button_text, "Registering ..."
  end

  override AshAuthentication.Phoenix.Components.Password.ResetForm do
    set :root_class, nil
    set :label_class, "mt-2 mb-4 text-2xl tracking-tight font-bold text-base-content"
    set :form_class, nil
    set :slot_class, "my-4"

    set :reset_flash_text,
        "If this user exists in our system, you will be contacted with reset instructions shortly."

    set :disable_button_text, "Requesting ..."
  end

  override AshAuthentication.Phoenix.Components.Password.Input do
    set :field_class, "mt-2 mb-2 text-base-content"
    set :label_class, "block text-sm font-medium text-base-content mb-1"

    set :input_class, """
    appearance-none block w-full px-3 py-2 border border-base-300 rounded-md
    shadow-sm placeholder-base-content/40 focus:outline-none focus:ring-primary/50
    focus:border-primary/50 sm:text-sm text-base-content
    """

    set :input_class_with_error, """
    appearance-none block w-full px-3 py-2 border border-error rounded-md
    shadow-sm placeholder-base-content/40 focus:outline-none sm:text-sm
    text-base-content
    """

    set :submit_class, """
    inline-flex w-full items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm
    font-medium focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-base-300
    disabled:pointer-events-none disabled:opacity-50 border border-base-300 bg-base-200/50
    shadow-sm hover:bg-base-200 hover:text-base-content h-9 px-4 py-2
    """

    set :password_input_label, "Password"
    set :password_confirmation_input_label, "Password Confirmation"
    set :identity_input_label, "Email"
    set :identity_input_placeholder, nil
    set :error_ul, "text-error font-light my-3 italic text-sm"
    set :error_li, nil
    set :input_debounce, 350
  end

  override AshAuthentication.Phoenix.Components.OAuth2 do
    set :root_class, "w-full mt-2 mb-4"

    set :link_class, """
    w-full flex justify-center py-2 px-4 border border-transparent rounded-md
    shadow-sm text-sm font-medium text-base-content bg-base-200 hover:bg-base-300
    focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary
    inline-flex items-center
    """

    set :icon_class, "-ml-0.4 mr-2 h-4 w-4"
  end

  override AshAuthentication.Phoenix.Components.Apple do
    set :root_class, "w-full mt-2 mb-4"

    set :link_class, """
    w-full flex justify-center px-4 border border-transparent rounded-md
    shadow-sm text-sm font-medium bg-base-content text-base-100 focus:outline-none
    focus:ring-2 focus:ring-offset-2 focus:ring-base-content inline-flex items-center
    """

    set :icon_class, ""
  end
end

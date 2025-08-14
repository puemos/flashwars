defmodule Flashwars.Test.Generator do
  use Ash.Generator

  alias Flashwars.Content.Tag

  def tag(opts \\ []) do
    changeset_generator(
      Tag,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end
end

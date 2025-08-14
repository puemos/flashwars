defmodule Flashwars.Test.Generator do
  use Ash.Generator

  alias Flashwars.Content.{Tag, Folder, StudySet, Term, SetTag}

  def tag(opts \\ []) do
    changeset_generator(
      Tag,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end

  def folder(opts \\ []) do
    changeset_generator(
      Folder,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end

  def study_set(opts \\ []) do
    changeset_generator(
      StudySet,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end

  def term(opts \\ []) do
    changeset_generator(
      Term,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end

  def set_tag(opts \\ []) do
    changeset_generator(
      SetTag,
      :create,
      overrides: opts,
      actor: opts[:actor]
    )
  end
end

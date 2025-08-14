defmodule Flashwars.Content do
  use Ash.Domain, otp_app: :flashwars
  require Ash.Query

  resources do
    resource Flashwars.Content.Folder
    resource Flashwars.Content.StudySet
    resource Flashwars.Content.Term
    resource Flashwars.Content.Tag
    resource Flashwars.Content.SetTag

    # Code interfaces for Tag
    resource Flashwars.Content.Tag do
      define :create_tag, action: :create
      define :update_tag, action: :update
      define :destroy_tag, action: :destroy
      define :list_tags, action: :read
    end
  end

  alias Flashwars.Content.{StudySet, Term}
  # Tagging resources are part of the domain, no direct code interface used here

  # StudySet code interface
  def create_study_set(params, opts \\ []) do
    StudySet
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create()
  end

  def create_study_set!(params, opts \\ []) do
    case create_study_set(params, opts) do
      {:ok, record} -> record
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  def update_study_set(study_set, params, opts \\ []) do
    study_set
    |> Ash.Changeset.for_update(:update, params, opts)
    |> Ash.update()
  end

  def archive_study_set(study_set, opts \\ []) do
    study_set
    |> Ash.Changeset.for_destroy(:archive, %{}, opts)
    |> Ash.destroy()
  end

  def list_study_sets(opts \\ []) do
    StudySet
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.read()
  end

  def get_study_set(id, opts \\ []) do
    StudySet
    |> Ash.get(id, opts)
  end

  # Term code interface
  def create_term(params, opts \\ []) do
    Term
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create()
  end

  def update_term(term, params, opts \\ []) do
    term
    |> Ash.Changeset.for_update(:update, params, opts)
    |> Ash.update()
  end

  def delete_term(term, opts \\ []) do
    term
    |> Ash.Changeset.for_destroy(:destroy, %{}, opts)
    |> Ash.destroy()
  end

  def list_terms(study_set_id, opts \\ []) do
    Term
    |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, opts)
    |> Ash.read()
  end
end

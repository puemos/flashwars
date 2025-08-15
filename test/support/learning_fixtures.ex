defmodule Flashwars.Test.LearningFixtures do
  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  @pairs [
    {"apple", "mela"},
    {"book", "libro"},
    {"house", "casa"},
    {"cat", "gatto"},
    {"dog", "cane"},
    {"water", "acqua"},
    {"food", "cibo"},
    {"friend", "amico"},
    {"sun", "sole"},
    {"moon", "luna"},
    {"car", "auto"},
    {"train", "treno"},
    {"school", "scuola"},
    {"work", "lavoro"},
    {"music", "musica"},
    {"city", "città"},
    {"family", "famiglia"},
    {"happy", "felice"},
    {"sad", "triste"},
    {"beautiful", "bello"},
    {"time", "tempo"},
    {"world", "mondo"},
    {"child", "bambino"},
    {"love", "amore"},
    {"day", "giorno"},
    {"night", "notte"},
    {"man", "uomo"},
    {"woman", "donna"},
    {"life", "vita"},
    {"hand", "mano"},
    {"place", "luogo"},
    {"year", "anno"},
    {"thing", "cosa"},
    {"people", "gente"},
    {"mother", "madre"},
    {"father", "padre"},
    {"door", "porta"},
    {"window", "finestra"},
    {"letter", "lettera"},
    {"word", "parola"},
    {"computer", "computer"},
    {"phone", "telefono"},
    {"table", "tavolo"},
    {"chair", "sedia"},
    {"king", "re"},
    {"queen", "regina"},
    {"road", "strada"},
    {"river", "fiume"},
    {"mountain", "montagna"},
    {"beach", "spiaggia"}
  ]

  def pairs, do: @pairs

  def build_set(_) do
    unique = System.unique_integer([:positive])
    org = Ash.Seed.seed!(Organization, %{name: "LearnOrg-#{unique}"})
    host = Ash.Seed.seed!(User, %{email: "learn#{unique}@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Italian", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    terms =
      Enum.with_index(@pairs, 1)
      |> Enum.map(fn {{term, defn}, idx} ->
        Content.create_term!(
          %{study_set_id: set.id, term: term, definition: defn, position: idx},
          authorize?: false
        )
      end)

    %{
      org: org,
      user: host,
      set: set,
      terms: Map.new(terms, &{&1.term, &1}),
      terms_by_id: Map.new(terms, &{&1.id, &1})
    }
  end
end

# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Flashwars.Repo.insert!(%Flashwars.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Flashwars.Repo
alias Flashwars.Content.{Folder, StudySet, Term, SetTag, Tag}
alias Flashwars.Accounts.User

# Create a user to own folders/study sets
owner =
  Repo.insert!(%User{
    id: Ecto.UUID.generate(),
    email: "owner@example.com",
    site_admin: false
  })

# Create a folder
folder =
  Repo.insert!(%Folder{
    name: "Seed Folder",
    owner_id: owner.id
  })

# Create a study set in the folder
study_set =
  Repo.insert!(%StudySet{
    name: "Seed Study Set",
    description: "A study set for seeds",
    privacy: :public,
    owner_id: owner.id,
    folder_id: folder.id
  })

# Create a term in the study set
term =
  Repo.insert!(%Term{
    term: "Seed Term",
    definition: "A term for seeding",
    position: 1,
    study_set_id: study_set.id
  })

# Create a tag
tag =
  Repo.insert!(%Tag{
    name: "Seed Tag"
  })

# Create a set_tag association
set_tag =
  Repo.insert!(%SetTag{
    study_set_id: study_set.id,
    tag_id: tag.id
  })

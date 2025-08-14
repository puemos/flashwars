defmodule Flashwars.Content.TagTest do
  use Flashwars.DataCase, async: true
  import ExUnitProperties

  alias Flashwars.Content
  alias Flashwars.Content.Tag

  @admin %{id: Ecto.UUID.generate(), site_admin: true}
  @user %{id: Ecto.UUID.generate(), site_admin: false}

  describe "valid inputs" do
    property "accepts all valid input" do
      check all(input <- Ash.Generator.action_input(Tag, :create)) do
        cs = Ash.Changeset.for_create(Tag, :create, input, authorize?: false, actor: @admin)
        assert cs.valid?
      end
    end

    property "succeeds on all valid input" do
      check all(input <- Ash.Generator.action_input(Tag, :create)) do
        tag = Content.create_tag!(input, actor: @admin)
        assert %Tag{} = tag
      end
    end

    test "can create a tag with a specific name" do
      tag = Content.create_tag!(%{name: "vocabulary"}, actor: @admin)
      assert tag.name == "vocabulary"
    end
  end

  describe "authorization" do
    test "non-admins cannot create tags" do
      refute Content.can_create_tag?(@user)
    end

    test "admins can create tags" do
      assert Content.can_create_tag?(@admin)
    end

    test "admins can update tags" do
      tag = Content.create_tag!(%{name: "x"}, actor: @admin)
      assert Content.can_update_tag?(@admin, tag)
      refute Content.can_update_tag?(@user, tag)
    end
  end
end

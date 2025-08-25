defmodule FlashwarsWeb.FlashcardsLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  alias Flashwars.Test.LearningFixtures

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end
end

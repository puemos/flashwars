# Flashwars

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learning engine

```elixir
alias Flashwars.Learning.Engine

# Flashcards
Engine.generate_flashcard(user, study_set_id, smart: true)

# Learn round
Engine.generate_learn_round(user, study_set_id, size: 5, smart: true)

# Test mode
Engine.generate_test(user, study_set_id, size: 10, smart: true)
```

Pass `smart: false` to bypass scheduler-driven prioritization and use basic ordering.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

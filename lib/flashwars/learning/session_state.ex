defmodule Flashwars.Learning.SessionState do
  use Ash.TypedStruct

  typed_struct do
    field :round_items, {:array, :map}, default: []
    field :round_index, :integer, constraints: [min: 0], default: 0
    field :round_number, :integer, constraints: [min: 1], default: 1
    field :round_position, :integer, constraints: [min: 1], default: 1
    field :round_correct_count, :integer, constraints: [min: 0], default: 0
    field :current_item, :map, allow_nil?: true

    field :session_stats, :struct,
      default: %{total_correct: 0, total_questions: 0},
      constraints: [
        fields: [
          total_correct: [type: :integer, constraints: [min: 0]],
          total_questions: [type: :integer, constraints: [min: 0]]
        ]
      ]

    field :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test]],
      default: :learn

    field :phase, :atom,
      constraints: [one_of: [:first_pass, :retry]],
      default: :first_pass

    field :round_deferred, {:array, :map}, default: []
    field :retry_queue, {:array, :map}, default: []
    field :retry_index, :integer, constraints: [min: 0], default: 0
  end
end

# Review

## Summary
- Removed legacy `:match` mode and added seedable study modes with telemetry.
- Introduced optional `smart` flag with Ash query optimizations for ordering.
- Expanded engine tests using a large English–Italian vocabulary and a full learning flow.
- Added documentation, project guide, and changelog entry.

## Test Coverage
- `mix test` – 30 tests, 2 properties
- `mix precommit` – format, compile, and tests all pass

## Key Decisions
- Optional RNG seed via `:seed` option using `:rand.seed/2`.
- Telemetry events for flashcard, learn round, and test builds.
- Scheduler queue handles card states and raw terms.

## Tradeoffs
- Test mode seed does not guarantee due terms appear; priority verified via scheduler.
- Matching selection falls back to multiple choice if insufficient terms.
- Smart flag fallback uses alphabetical ordering which may not suit all use cases.

## Risks
- Scheduling heuristics may need tuning for larger datasets.
- Large fixture set increases test setup time.

## Quality Checklist
- [x] No term repeats within learn rounds or tests.
- [x] Matching pair counts respected.
- [x] Multiple choice always four options and shuffles.
- [x] Free text carries canonical answer.
- [x] True/false uses only "True" and "False".
- [x] Determinism supported via optional seed.
- [x] Performance acceptable for typical set sizes.

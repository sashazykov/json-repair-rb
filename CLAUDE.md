# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `bin/setup` — install dependencies via Bundler.
- `bundle exec rake` — default task; runs RSpec, RuboCop, RBS validate, and Steep.
- `bundle exec rspec` — run the test suite.
- `bundle exec rspec spec/json_spec.rb:42` — run a single example by line number; nearly all behavioral specs live in `spec/json_spec.rb`.
- `bundle exec rubocop` — lint. Project-specific exclusions in `.rubocop.yml` deliberately disable several `Metrics/*` cops for `lib/json/repairer.rb` and `lib/json/repair/string_utils.rb` because the parser is long by design — don't try to "fix" it by chopping methods up.
- `bin/console` — IRB with the gem preloaded.
- `bundle exec rake bench` — benchmark-ips regression baseline (`benchmark/run.rb`); run before/after perf-sensitive changes.
- `bundle exec rake install` / `bundle exec rake release` — local install / publish to rubygems.org (release prompts for a rubygems MFA OTP).
- Type checking: `Steepfile` checks `lib/` against `sig/`. `bundle exec steep check` (typecheck) and `bundle exec rbs validate` (sig syntax) both run in CI and as part of the default rake task. `steep` and `rbs` are dev dependencies in the `Gemfile`.

Ruby `>= 3.0.0` is required (per gemspec). CI runs against all currently maintained Ruby branches (3.3, 3.4, 4.0).

## Architecture

This gem is a **Ruby port of the [josdejong/jsonrepair](https://github.com/josdejong/jsonrepair) TypeScript library**. The upstream version currently mirrored is tracked in `CHANGELOG.md` (presently v3.14.0). When syncing upstream changes, the goal is parity with the JS implementation, not idiomatic refactoring — keep method names, control flow, and repair heuristics aligned with the JS source so future syncs stay tractable.

A few repair heuristics deliberately go **beyond** upstream (leading-dot numbers like `.5`, Markdown list markers like `- {...}`). Each such site carries a "Divergence from upstream" comment in the code and a CHANGELOG note — keep that convention when adding more, so future upstream syncs can tell ported behavior from local extensions.

### Entry point

`JSON.repair(str)` in `lib/json/repair.rb` first tries stdlib `JSON.parse` (fast path; opt out with `skip_json_loads: true`), and falls back to `JSON::Repairer.new(str).repair` when that raises. Either way the result is re-serialized with `JSON.generate`, so **output is canonical** — whitespace collapsed, numbers normalized, duplicate keys last-write-wins — and both paths agree on it. There is no pre-filter regex: the fast path simply runs `JSON.parse` and falls back to the Repairer on any `JSON::ParserError`. Comments are handled either way — the bundled `json` gem currently accepts `//` and `/*` comments (an implementation detail, not part of the `JSON.parse` contract) and `JSON.generate` drops them (`{} // c` → `{}`); were a future `json` release to reject them, they would simply raise and route to the Repairer, which strips comments too. Invalid escapes, NDJSON, Markdown fences, and trailing prose already make `JSON.parse` raise and so route to the Repairer. `return_objects: true` returns the parsed Ruby value instead of a string; `JSON.repair_file(path)` / `JSON.repair_io(io)` are convenience wrappers forwarding both options.

`JSON::JSONRepairError` is the only error raised for unrecoverable inputs; it exposes the failure `#position`. If the Repairer ever emits a string stdlib cannot parse (a Repairer bug), the `JSON::ParserError` is wrapped in `JSONRepairError` rather than leaked.

`exe/json-repair` is a CLI wrapper (`lib/json/repair/cli.rb`) reading stdin or a file, writing stdout, `--output FILE`, or `--overwrite`.

### The parser (`lib/json/repairer.rb`)

A single-pass, hand-written recursive-descent parser. State is three instance variables:

- `@json` — the input string (read-only after init).
- `@index` — the current cursor into `@json`.
- `@output` — a mutable `+''` buffer that accumulates the *repaired* JSON. The parser writes directly to `@output` as it walks; it does not build an AST.

Each `parse_*` method (`parse_value`, `parse_object`, `parse_array`, `parse_string`, `parse_number`, `parse_keywords`, `parse_unquoted_string`, `parse_regex`, `parse_comment`, `parse_markdown_code_block`, …) follows a contract:

1. Returns truthy if it consumed something, falsy otherwise.
2. On success, advances `@index` past the consumed input and appends the *valid* JSON form to `@output`.
3. On a recoverable mismatch (missing quote, missing comma, trailing comma, wrong quote style, etc.) it performs an in-place repair on `@output` using helpers like `insert_before_last_whitespace`, `strip_last_occurrence`, or `remove_at_index`.
4. On an unrecoverable error it calls one of the `throw_*` helpers, which raise `JSON::JSONRepairError`.

Two patterns recur and are worth knowing before editing:

- **Backtracking via snapshots.** Methods like `parse_string` capture `i_before = @index` and `o_before = @output.length` before tentatively consuming input. If a later check (e.g. "the end quote turned out not to be a real end quote") fails, they restore both and re-invoke themselves with different flags (e.g. `stop_at_delimiter: true`, `stop_at_index: …`). Preserve this pattern when modifying string/number parsing.
- **Repair-by-rewriting-tail.** Helpers like `insert_before_last_whitespace(@output, ',')` and `@output = strip_last_occurrence(@output, ',')` patch the already-emitted output to fix things like missing or trailing commas. These run *after* the malformed input has been partially emitted — they are the mechanism for "I now realize that earlier token needed a comma after it."

`repair` (the public method) drives `parse_value` then handles top-level concerns: stripping Markdown fences (` ```json ... ``` `), skipping Markdown list markers like `- ` / `* ` / `1. ` before the root value and each newline-delimited line (`markdown_list_marker_length` / `skip_markdown_list_marker` — top-level only, never inside nested structures), converting newline-delimited JSON at the root into an array, dropping redundant trailing braces/brackets, and rejecting any non-whitespace trailing garbage.

### Shared helpers (`lib/json/repair/string_utils.rb`)

`JSON::Repair::StringUtils` is a mixin included into `Repairer`. It holds:

- Character constants (`OPENING_BRACE`, `BACKSLASH`, smart-quote variants, special whitespace code points, etc.) used in lieu of magic literals.
- Character-class predicates (`digit?`, `hex?`, `quote?`, `single_quote_like?`, `delimiter?`, `whitespace?`, `special_whitespace?`, `start_of_value?`, …).
- The keyword machinery — `parse_keywords` / `parse_keyword` — which converts Python `True`/`False`/`None` and Ruby `nil` into their JSON equivalents in addition to recognizing `true`/`false`/`null`.
- Output-buffer surgery helpers: `strip_last_occurrence`, `insert_before_last_whitespace`, `remove_at_index`, `ends_with_comma_or_newline?`.

Because the mixin reads `@json`, `@index`, and `@output` directly (notably inside `parse_keyword`), it is **not standalone** — it is coupled to `Repairer`'s state and should only be mixed into classes that own those ivars.

### Type signatures (`sig/`)

RBS signatures mirror the public surface of `JSON.repair`, `JSON::Repairer`, and `JSON::Repair::StringUtils`. Update them in lockstep with `lib/` changes; the `Steepfile` will surface drift.

### Test layout

- `spec/json_spec.rb` — the substantive behavioral suite (130+ examples, hundreds of assertions, covering every repair heuristic). New behavior — and every sync from upstream — belongs here.
- `spec/json/repair/cli_spec.rb` — the `exe/json-repair` CLI (argument handling, IO errors, exit codes).
- `spec/json/repair/string_utils_spec.rb` — direct unit coverage for a few `StringUtils` edge cases the behavioral suite can't reach.
- `spec/json/repair_spec.rb` — sanity check on `JSON::Repair::VERSION` only.
- SimpleCov enforces 100% line and branch coverage on the full run, so a filtered `rspec -e ...` run "fails" at the coverage gate even when all selected examples pass — ignore that exit code during TDD.
- `.rspec_status` is gitignored (local pass/fail tracking for `--only-failures` / `--next-failure`).

## Local planning notes

`docs/` (the `TODO.md` backlog plus design specs and implementation plans under `docs/superpowers/`) is gitignored local planning material — read it for context, update it as work completes, but never commit anything under `docs/`.

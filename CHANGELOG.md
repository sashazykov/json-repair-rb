# Changes

### 2026-06-12 (0.11.1)

* Fix a `TypeError` crash on input ending in a lone backslash inside a
  string: `"abc\` now repairs to `"abc"` (likewise `"\` → `""`,
  `["abc\` → `["abc"]`, `{"a": "b\` → `{"a":"b"}`), matching upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) v3.14.0. This
  was a porting bug — JS `charAt` past EOF returns `''` where Ruby
  `String#[]` returns `nil`, so the invalid-escape repair in
  `parse_string` crashed on `str << nil` instead of ending the string,
  violating the contract that `JSONRepairError` is the only error
  raised. Found by differential fuzzing during the 0.11.0 review.

### 2026-06-12 (0.11.0)

* Repair object string values with unescaped quotes around a colon
  ("doubled colon"): `{"a": "b": "c"}` → `{"a":"b\": \"c"}` — the
  value reads as `b": "c`, the unescaped-quotes interpretation. The
  merge preserves the literal characters between the strings
  (whitespace, original quote style) and repeats greedily
  (`{"a": "b": "c": "d"}` → value `b": "c": "d`). Only the
  string–colon–string shape is repaired: non-string shapes like
  `{"a": "b": 1}` or `{"a": 1: 2}` still raise `JSONRepairError`
  rather than silently dropping data (Python `json_repair` drops the
  `: 1` there). Previously all of these raised "Object key expected".
  Deliberate divergence from upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) (raises as of
  v3.14.0), matching
  [Go json-repair](https://github.com/RealAlexandreAI/json-repair)
  and Python
  [`json_repair`](https://github.com/mangiucugna/json_repair) on the
  canonical case.

### 2026-06-11 (0.10.0)

* Repair Markdown list markers in front of top-level values:
  `- {"a": 1}` → `{"a":1}`, and multi-line lists become arrays via the
  existing newline-delimited JSON handling
  (`"- {\"a\": 1}\n- {\"b\": 2}"` → `[{"a":1},{"b":2}]`). Bullet
  markers `-`, `*`, `+` and ordered markers like `1.` / `2)` (up to
  nine digits, the CommonMark limit) are recognized at the start of
  the root value and of each newline-delimited line, only when
  followed by same-line whitespace and a value — so `-5`, a trailing
  `"- "`, and newline-delimited decimals like `"1.5\n2.5"` keep their
  number readings, and nothing changes inside nested structures.
  Previously these inputs raised `JSONRepairError`; two non-raising
  behaviors change for the better: `"3\n- 5\n7"` now repairs to
  `[3,5,7]` instead of the corrupt `[3,0,5,7]`, and a single-line
  `* text` becomes `"text"` instead of `"* text"`. Deliberate
  divergence from upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) (no Markdown
  list handling as of v3.14.0), and more precise than Python
  [`json_repair`](https://github.com/mangiucugna/json_repair), which
  collapses scalar list items to `""`.

### 2026-06-11 (0.9.0)

* Repair numbers missing the digit before their decimal point:
  `.5` → `0.5`, `-.5` → `-0.5`, and truncated forms like `.` → `0.0`.
  Previously these leaked a raw stdlib `JSON::ParserError` out of
  `JSON.repair` because the repairer emitted the leading-dot number
  unchanged (invalid JSON) and the canonical-output re-parse choked on
  it. This is a deliberate divergence from upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) (which leaves
  leading-dot numbers unrepaired as of v3.14.0), matching
  [dirty-json](https://github.com/RyanMarcus/dirty-json) behavior.
* `JSON.repair` now guards its error contract: if the repairer ever
  emits a string stdlib JSON cannot parse (a repairer bug), the stdlib
  error is wrapped in `JSON::JSONRepairError` instead of leaking
  `JSON::ParserError` to callers.

### 2026-05-15 (0.8.0)

* `JSON.repair_file(path)` and `JSON.repair_io(io)` convenience
  wrappers around `JSON.repair`. `repair_file` reads a path from disk
  (accepts a `String` or `Pathname`); `repair_io` reads from any
  object responding to `#read` (e.g. `File`, `StringIO`, `$stdin`)
  without closing it. Both forward `return_objects:` and
  `skip_json_loads:` through to `JSON.repair`. Mirrors Python's
  [`json_repair`](https://github.com/mangiucugna/json_repair)
  `load` / `from_file` helpers.

### 2026-05-12 (0.7.0)

* `JSON.repair` now always returns canonical JSON via
  `JSON.generate`. When the input is already valid JSON, stdlib
  `JSON.parse` handles it directly; when it isn't, the repairer
  produces an intermediate string that's then re-parsed and serialized
  the same way. Both paths converge on the same output for any given
  input, so `JSON.repair(json)` and
  `JSON.repair(json, skip_json_loads: true)` agree on result and only
  differ in how they got there.
* **Breaking:** outputs are now canonical instead of preserving the
  input's exact formatting. Whitespace is collapsed
  (`'{"a": 1}'` → `'{"a":1}'`), numbers are normalized
  (`2300e3` → `2300000.0`, `-0` → `0`), `\uXXXX` escapes are decoded
  to their literal characters, `\/` is unescaped to `/`, and objects
  with duplicate keys are collapsed to the last-write-wins form
  (`{"a":1,"a":2}` → `{"a":2}`). Callers that need a parsed Ruby
  value can opt out of the final `JSON.generate` step with
  `return_objects: true`.
* `skip_json_loads:` keyword argument added (default `false`,
  mirroring Python's
  [`json_repair`](https://github.com/mangiucugna/json_repair)
  option). Passing `true` skips the stdlib `JSON.parse` fast attempt
  and routes the input through the repairer first; the final output
  is identical, so the option is purely a performance knob for
  callers who know their input will need repair.

### 2026-05-12 (0.6.0)

* `JSON.repair` accepts a `return_objects:` keyword argument. Pass
  `return_objects: true` to receive the parsed Ruby value (Hash, Array,
  or scalar) instead of a serialized JSON string. Default is `false`,
  preserving the existing return-a-string contract. Mirrors Python's
  `return_objects` option on
  [`json_repair`](https://github.com/mangiucugna/json_repair).

### 2026-05-12 (0.5.0)

* `JSON::JSONRepairError#position` returns the input index at which the
  parser gave up, mirroring the `position` field on upstream
  [`jsonrepair`'s](https://github.com/josdejong/jsonrepair) JS error.
* **Possibly breaking:** the three error messages
  `Unexpected end of json string`, `Object key expected`, and
  `Colon expected` now include an `at index N` suffix, matching the
  format the other `throw_*` paths already used. Callers that
  pattern-match on the exact pre-suffix string will need to relax those
  matchers.

### 2026-05-12 (0.4.0)

* Add `json-repair` command-line executable. Reads from stdin or a
  filename and writes the repaired JSON to stdout, `-o FILE`, or back
  over the input file with `--overwrite`. Run `json-repair --help` for
  the full list of options.
* `--overwrite` follows symlinks and rewrites the target file, leaving
  the link itself intact.
* Non-UTF-8 input, broken symlinks, and parser stack overflow on deeply
  nested input now report a clean error on stderr and exit 1 instead of
  surfacing a Ruby backtrace.
* `--version` and `--help` short-circuit option parsing, so trailing
  arguments no longer flip the exit code or print spurious errors.

### 2026-05-10 (0.3.0)

Sync with upstream `jsonrepair` JS library (v3.8.0 → v3.14.0):

* Repair unquoted URLs and URLs with a missing end quote
* Repair strings containing colons or parentheses (e.g. `"12:20`, `"This is C(2)"`)
* Repair missing end quote of a string value containing commas in an object
  (e.g. `{"a":"b,c,"d":"e"}` → `{"a":"b,c","d":"e"}`)
* Repair missing comma at a newline between object properties
* Strip Markdown fenced code blocks (` ```json ... ``` `), including invalid
  placements and leading whitespace
* Repair regular expressions as a separate value type, escaping quotes to
  prevent XSS via `eval`
* Repair backslash-escaped newline characters
* Recognize additional special whitespace characters (Mongolian vowel separator,
  zero-width space, ZWNBSP, and more)
* Throw `Invalid character` for unescaped `U+0000`–`U+001F` control chars in strings

### 2024-06-01 (0.2.0)

* Moved the repair method to the JSON module

### 2024-05-23 (0.1.0)

* Initial setup

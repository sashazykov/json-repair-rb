# Changes

### 2026-06-12 (0.13.0)

* Repair `#` hash line comments, like in Python, YAML, or Hjson:
  `{"a": 1 # comment\n}` → `{"a":1}`, `{ # note\n "a": 1}` →
  `{"a":1}`, `# lead\n{"a": 1}` → `{"a":1}`. Divergence from upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) (v3.14.0
  raises on all of these), commented at the site. Recognition is
  context-aware so unquoted values starting with `#` keep repairing
  into strings — `{"color": #ff0000}` → `{"color":"#ff0000"}`,
  `{#tag: 1}` → `{"#tag":1}`, `#standalone` → `"#standalone"` — where
  Python's `json_repair` silently loses them (`{"color": ""}`).
  Where a value or key is expected, a `#` token reaching a structural
  delimiter (`,` `}` `]` `:`) before any whitespace, or running to
  end-of-input without a newline, stays a value; anything else is a
  comment stripped to the end of the line. The tradeoff: a `#` token
  followed by whitespace or a newline at a value position now reads
  as a comment — `{"a": #b c}` → `{"a":null}` and `{"a": #tag\n}` →
  `{"a":null}`, where 0.12.0 kept them as strings (Python drops them
  too), and a comment-only document now raises like `// only a
  comment` always has. Pinned in the spec suite as conscious
  decisions.

### 2026-06-12 (0.12.0)

* Repair the three known input families that raised `Internal error:
  repaired output is not valid JSON` — cases where upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) (v3.14.0, still
  its latest release) emits invalid JSON and this gem's canonical
  re-serialize guard caught it but blamed the Repairer. All three are
  deliberate divergences from upstream, commented at each site:
  * A stray `e`/`E` with no mantissa is now an unquoted string instead
    of an empty-mantissa exponent: `[e]` → `["e"]`, `[e5]` → `["e5"]`,
    `[truee]` → `[true,"e"]`, `{"k": e}` → `{"k":"e"}` (upstream emits
    `e0` / raw `e5`). Numbers truncated at a real exponent (`[2e]` →
    `[2.0]`) are unchanged.
  * Negative leading-zero numbers are quoted like positive ones:
    `{"n": -05}` → `{"n":"-05"}`, matching the existing `{"n": 05}` →
    `{"n":"05"}` (upstream emits `-05` unrepaired). The same rule now
    also covers the truncated-number repair, which bypassed it:
    `[05e]` → `["05e0"]`, `00.` → `"00.0"` (upstream emits `05e0` /
    `00.0` unrepaired). Valid `-0` / `-0.5` / `0e` / `0.` are
    unchanged.
  * The trailing-comma repair no longer strips a comma belonging to the
    enclosing container when an inner object/array fails on its first
    key or value: `[{{]` → `[{},{}]`, `[1,[}]` → `[1,[]]`,
    `{"a": 1, "b": [}` → `{"a":1,"b":[]}` (upstream emits `[{}{}]`,
    `[1[]]`, `{"a": 1 "b": []}`).
  Validated by differential testing against upstream over a 270-input
  grid of these shapes in every container context: the only behavior
  changes vs 0.11.3 are the 123 previously-`Internal error` inputs now
  repairing (or, for `e+` shapes where upstream emits invalid `e+0`,
  raising a clean position-bearing error). Benchmarks flat.

### 2026-06-12 (0.11.3)

* Fix infinite recursion (`SystemStackError`) on a quoted string
  followed by a backslash-escaped delimiter, like `["y"\, "z"]`. The
  missing-end-quote retry in `parse_string` stops at the comma it
  detected in the first pass, but the invalid-escape repair consumed
  `\,` as one two-character step, jumping over the stop index and
  re-firing the retry with identical arguments forever — violating the
  contract that `JSONRepairError` is the only error raised. The escaped
  delimiter now ends the string there and the dangling backslash is
  dropped (the standard invalid-escape repair): `["y"\, "z"]` →
  `["y\"","z"]`. The stop-index check is also hardened from `==` to
  `>=` so no future multi-character advance can step over it and
  recurse. Deliberate divergence from upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair), which crashes
  with "Maximum call stack size exceeded" on the same input as of
  v3.14.0 (still its latest release). Found by differential fuzzing
  during the 0.11.2 work and re-validated the same way: across a
  240-input grid of escape-adjacent shapes, only previously-crashing
  inputs changed behavior — object shapes like `{"k": "y"\, "z"}` now
  raise the same "Colon expected" as their backslash-free analog
  `{"k": "y", "z"}`. Benchmarks flat vs 0.11.2.

### 2026-06-12 (0.11.2)

* Fix the 0.11.0 doubled-colon repair silently mangling objects with a
  stray junk word between pairs. `{"value_1": true, COMMENT "value_2":
  "data"}` returned `{"value_1":true,"COMMENT":"value_2\": \"data"}`
  (the junk word became a key and swallowed the real pair), and
  `{ "key": "value" COMMENT "key2": "value2" }` returned a single
  glued string value. Both shapes now raise "Object key expected"
  again at the same positions as upstream
  [jsonrepair](https://github.com/josdejong/jsonrepair) v3.14.0,
  restoring the pre-0.11.0 behavior: the merge is skipped when the
  pair already needed a missing-colon repair or the value string was
  itself salvaged by the unescaped-quote repair — signals that the
  pair was malformed in a way the merge would compound, not fix. The
  salvage signal survives string concatenation: in
  `{"a": "b" x "c" + "d": "e"}` the `+ "d"` segment no longer clears
  it (caught in review by Copilot). All
  0.11.0 repairs (canonical, greedy, escaped quotes, unquoted
  keys/values) are unchanged. Go and Python `json_repair` instead
  drop the junk word; we deliberately keep raising rather than
  silently discarding input (see the 0.11.0 note).

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

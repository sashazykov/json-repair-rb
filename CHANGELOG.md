# Changes

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

# JSON::Repair [![Gem Version](https://badge.fury.io/rb/json-repair.svg)](https://badge.fury.io/rb/json-repair) [![Build Status](https://github.com/sashazykov/json-repair-rb/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/sashazykov/json-repair-rb/actions) [![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://stand-with-ukraine.pp.ua)

This is a Ruby gem designed to repair broken JSON strings. Inspired by and based on the [jsonrepair js library](https://github.com/josdejong/jsonrepair/). It efficiently handles and corrects malformed JSON data, making it especially useful in scenarios where JSON output from LLMs might not strictly adhere to JSON standards. Whether it's missing quotes, misplaced commas, or unexpected characters, it ensures that the JSON data is valid and can be parsed correctly.

## Installation

Add this gem to your application's Gemfield by executing:

```bash
$ bundle add json-repair
```

Alternatively, if you are not using Bundler to manage your dependencies:

```bash
$ gem install json-repair
```

## Usage

Using JSON::Repair is straightforward. Simply call the `repair` method with a JSON string as an argument:

```ruby
require 'json/repair'

# Example of repairing a JSON string
broken_json = '{name: Alice, "age": 25,}'
repaired_json = JSON.repair(broken_json)
puts repaired_json  # Outputs: {"name":"Alice","age":25}
```

The `repair` method takes a string containing JSON data and returns a corrected version of this string, ensuring it is valid JSON.

Pass `return_objects: true` to get the parsed Ruby value (Hash, Array, or scalar) instead of a string:

```ruby
JSON.repair('{a: 1, b: [2, 3,]}', return_objects: true)
# => {"a" => 1, "b" => [2, 3]}
```

### Canonical output

`JSON.repair` returns canonical JSON via `JSON.generate`. When the input is already valid, stdlib `JSON.parse` handles it; otherwise the repairer fixes it up and the result is re-serialized the same way. Either way, the output is the canonical form of the parsed value — whitespace is collapsed, numbers are normalized, `\uXXXX` escapes are decoded to literal characters, and objects with duplicate keys collapse to last-write-wins.

```ruby
JSON.repair('{"a": 1}')          # => '{"a":1}'
JSON.repair('{a:1}')             # => '{"a":1}'
JSON.repair('2300e3')            # => '2300000.0'
JSON.repair('{"a":1,"a":2}')     # => '{"a":2}'
```

If you need the parsed Ruby value instead of a string, pass `return_objects: true` (covered above).

`skip_json_loads: true` skips the stdlib `JSON.parse` attempt and routes the input straight through the repairer. The output is the same; the option is purely a performance knob for callers who know their input will need repair.

### Reading from a file or IO

`JSON.repair_file(path)` reads a file from disk and repairs its contents. `JSON.repair_io(io)` does the same with any object that responds to `#read` (e.g. `File`, `StringIO`, `$stdin`). Both forward `return_objects:` and `skip_json_loads:` to `JSON.repair`.

```ruby
JSON.repair_file('broken.json')
JSON.repair_file('broken.json', return_objects: true)

File.open('broken.json') { |io| JSON.repair_io(io) }
JSON.repair_io($stdin)
```

`JSON.repair_io` does not close the IO — the caller manages its lifecycle.

## Command line

The gem ships a `json-repair` executable. It reads from stdin or a file and writes to stdout, `--output FILE`, or back over the input file with `--overwrite`.

```bash
$ echo '{a:1,}' | json-repair
{"a":1}

$ json-repair broken.json
$ json-repair broken.json -o fixed.json
$ json-repair broken.json --overwrite
```

Run `json-repair --help` for the full list of options.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Run `bundle exec rake bench` for a `benchmark-ips` regression baseline across four canned scenarios (valid mixed JSON, broken LLM-style output, a large array, deeply nested objects). The harness lives under `benchmark/` and is not shipped in the published gem.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sashazykov/json-repair-rb. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/sashazykov/json-repair-rb/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [ISC License](https://opensource.org/licenses/ISC).

## Code of Conduct

Everyone interacting in the JSON::Repair project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/sashazykov/json-repair-rb/blob/main/CODE_OF_CONDUCT.md).

## Similar libraries in other languages

- Typescript: https://github.com/josdejong/jsonrepair
- Go: https://github.com/RealAlexandreAI/json-repair
- JavaScript: https://github.com/RyanMarcus/dirty-json
- Python: https://github.com/mangiucugna/json_repair

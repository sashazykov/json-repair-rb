# JSON::Repair [![Gem Version](https://badge.fury.io/rb/json-repair.svg)](https://badge.fury.io/rb/json-repair) [![Build Status](https://github.com/sashazykov/json-repair-rb/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/sashazykov/json-repair-rb/actions) [![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

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
puts repaired_json  # Outputs: {"name": "Alice", "age": 25}
```

The `repair` method takes a string containing JSON data and returns a corrected version of this string, ensuring it is valid JSON.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

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

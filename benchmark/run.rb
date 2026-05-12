# frozen_string_literal: true

# Benchmark harness for JSON.repair.
#
# Run with: bundle exec rake bench
#
# Reports operations/sec across four scenarios. Useful as a regression baseline
# before perf work — record numbers from main, change something, re-run.

require 'benchmark/ips'
require 'json'
require_relative '../lib/json/repair'

# --- Inputs ----------------------------------------------------------------

def sample_record(idx)
  {
    'id' => idx,
    'name' => "user_#{idx}",
    'email' => "user_#{idx}@example.com",
    'active' => idx.even?,
    'score' => idx * 1.5,
    'tags' => %w[alpha beta gamma].first(idx % 3 + 1),
    'meta' => {
      'note' => "line one\nline two\ttab\t\"quoted\"",
      'unicode' => "snowman ☃ emoji \u{1F600}",
      'sci' => 1.23e-4,
      'neg' => -idx,
      'flag' => nil
    }
  }
end

VALID_MIXED = JSON.generate(
  {
    'users' => Array.new(20) { |i| sample_record(i) },
    'page' => 1,
    'total' => 20,
    'has_more' => false
  }
)

BROKEN_LLM_STYLE = <<~JSON
  ```json
  {
    users: [
      { 'id': 1, name: "Alice", "email": 'alice@example.com', tags: ["a", "b", "c",], active: True, },
      { 'id': 2, name: "Bob",   "email": 'bob@example.com',   tags: ["d", "e",],      active: False, },
      { 'id': 3, name: "Carol", "email": 'carol@example.com', tags: ["f",],           active: None, },
    ],
    // page info
    page: 1,
    total: 3,
    note: "smart quotes “hi” and a trailing comma",
  }
  ```
JSON

LARGE_ARRAY = JSON.generate(Array.new(1_000) { |i| sample_record(i) })

DEEPLY_NESTED = "#{'{"a":' * 50}1#{'}' * 50}".freeze

SCENARIOS = {
  'valid_mixed' => VALID_MIXED,
  'broken_llm_style' => BROKEN_LLM_STYLE,
  'large_array' => LARGE_ARRAY,
  'deeply_nested' => DEEPLY_NESTED
}.freeze

# --- Sanity check ----------------------------------------------------------
# Confirm every input round-trips through JSON.repair to valid JSON before we
# spend ten seconds benching it. A bench result on garbage is worse than no
# bench result.

SCENARIOS.each do |name, input|
  repaired = JSON.repair(input)
  JSON.parse(repaired)
  puts format(
    '%<name>-18s %<in>6d bytes in → %<out>6d bytes out',
    name: name, in: input.bytesize, out: repaired.bytesize
  )
rescue StandardError => e
  abort "scenario #{name.inspect} failed sanity check: #{e.class}: #{e.message}"
end
puts

# --- Benchmarks ------------------------------------------------------------

Benchmark.ips do |x|
  SCENARIOS.each do |name, input|
    x.report(name) { JSON.repair(input) }
  end
  x.compare!
end

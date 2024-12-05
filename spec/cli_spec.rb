# frozen_string_literal: true

require 'open3'

RSpec.describe 'CLI' do
  it 'repairs broken JSON from standard input' do
    broken_json = '{name: Alice, "age": 25,}'
    expected_output = '{"name": "Alice", "age": 25}'

    stdout, stderr, status = Open3.capture3('exe/json-repair', stdin_data: broken_json)

    expect(status.success?).to be true
    expect(stderr).to be_empty
    expect(stdout.strip).to eq(expected_output)
  end
end

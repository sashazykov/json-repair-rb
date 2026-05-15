# frozen_string_literal: true

require 'json'

require_relative 'repair/version'
require_relative 'repairer'

module JSON
  class JSONRepairError < StandardError
    attr_reader :position

    def initialize(message = nil, position = nil)
      super(message && position ? "#{message} at index #{position}" : message)
      @position = position
    end
  end

  def self.repair(json, return_objects: false, skip_json_loads: false)
    parsed = skip_json_loads ? repaired_parse(json) : tolerant_parse(json)
    return_objects ? parsed : JSON.generate(parsed)
  end

  # Inlined rather than calling `repair(...)` so the literal-bool overloads
  # in sig/json/repair.rbs narrow correctly per caller — forwarding a
  # `bool`-typed `return_objects` will not resolve against the literal-
  # `true`/`false` overloads on `JSON.repair`.
  def self.repair_io(io, return_objects: false, skip_json_loads: false)
    json = io.read || ''
    parsed = skip_json_loads ? repaired_parse(json) : tolerant_parse(json)
    return_objects ? parsed : JSON.generate(parsed)
  end

  def self.repair_file(path, return_objects: false, skip_json_loads: false)
    json = File.read(path.to_s)
    parsed = skip_json_loads ? repaired_parse(json) : tolerant_parse(json)
    return_objects ? parsed : JSON.generate(parsed)
  end

  def self.tolerant_parse(json)
    JSON.parse(json)
  rescue JSON::ParserError
    repaired_parse(json)
  end
  private_class_method :tolerant_parse

  def self.repaired_parse(json)
    JSON.parse(Repairer.new(json).repair)
  end
  private_class_method :repaired_parse
end

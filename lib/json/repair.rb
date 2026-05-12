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

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

  def self.repair(json, return_objects: false)
    repaired = Repairer.new(json).repair
    return_objects ? JSON.parse(repaired) : repaired
  end
end

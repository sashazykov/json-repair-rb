# frozen_string_literal: true

require_relative 'repair/version'
require_relative 'repairer'

module JSON
  class JSONRepairError < StandardError
    attr_reader :position

    def initialize(message = nil, position = nil)
      super(position.nil? ? message : "#{message} at index #{position}")
      @position = position
    end
  end

  def self.repair(json)
    Repairer.new(json).repair
  end
end

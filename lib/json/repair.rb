# frozen_string_literal: true

require_relative 'repair/version'
require_relative 'repair/repairer'

module JSON
  module Repair
    class JSONRepairError < StandardError; end

    def self.repair(json)
      Repairer.new(json).repair
    end
  end
end

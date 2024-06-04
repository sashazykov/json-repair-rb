# frozen_string_literal: true

require_relative 'repair/version'
require_relative 'repairer'

module JSON
  class JSONRepairError < StandardError; end

  def self.repair(json)
    Repairer.new(json).repair
  end
end

# frozen_string_literal: true

RSpec.describe JSON::Repair::StringUtils do
  let(:host) { JSON::Repairer.new('') }

  describe '#special_whitespace?' do
    it 'returns false when char is nil' do
      expect(host.special_whitespace?(nil)).to be(false)
    end

    it 'returns true for Unicode special whitespace characters' do
      expect(host.special_whitespace?(JSON::Repair::StringUtils::NON_BREAKING_SPACE)).to be(true)
      expect(host.special_whitespace?(JSON::Repair::StringUtils::IDEOGRAPHIC_SPACE)).to be(true)
    end

    it 'returns false for ordinary characters' do
      expect(host.special_whitespace?('a')).to be(false)
      expect(host.special_whitespace?(' ')).to be(false)
    end
  end
end

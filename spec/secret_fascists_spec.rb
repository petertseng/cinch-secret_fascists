require 'simplecov'
SimpleCov.start { add_filter '/spec/' }

require 'cinch/test'
require 'cinch/plugins/secret_fascists'

RSpec.configure { |c|
  c.warnings = true
  c.disable_monkey_patching!
}

RSpec.describe Cinch::Plugins::SecretFascists do
  include Cinch::Test

  let(:channel1) { '#test' }
  let(:players) { (1..5).map { |x| "player#{x}" } }
  let(:npmod) { 'npmod' }

  let(:opts) {{
    :channels => [channel1],
    :settings => '/dev/null',
    :mods => [npmod, players[0]],
    :allowed_idle => 300,
  }}
  let(:bot) {
    make_bot(described_class, opts) { |c| self.loggers.first.level = :warn }
  }
  let(:plugin) { bot.plugins.first }

  it 'makes a test bot' do
    expect(bot).to be_a(Cinch::Bot)
  end
end

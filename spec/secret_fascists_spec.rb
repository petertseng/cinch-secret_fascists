require 'simplecov'
SimpleCov.start { add_filter '/spec/' }

require 'cinch/test'
require 'cinch/plugins/secret_fascists'

RSpec.configure { |c|
  c.warnings = true
  c.disable_monkey_patching!
}

class MessageReceiver
  attr_reader :name
  attr_accessor :messages

  def initialize(name)
    @name = name
    @messages = []
  end

  def send(m)
    @messages << m
  end
end

class TestChannel < MessageReceiver
end

RSpec.describe Cinch::Plugins::SecretFascists do
  include Cinch::Test

  let(:channel1) { '#test' }
  let(:chan) { TestChannel.new(channel1) }
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

  def pm(text, nick: players[0])
    make_message(bot, text, nick: nick)
  end
  def msg(text, nick: players[0], channel: channel1)
    make_message(bot, text, nick: nick, channel: channel)
  end

  def join(player)
    message = msg('!join', nick: player)
    expect(message.channel).to receive(:has_user?).with(message.user).and_return(true)
    expect(message.channel).to receive(:voice).with(message.user)
    get_replies(message)
  end

  it 'makes a test bot' do
    expect(bot).to be_a(Cinch::Bot)
  end

  context 'in game' do
    before(:each) do
      allow(plugin).to receive(:Channel).with(channel1).and_return(chan)
      players.each { |player| join(player) }
      chan.messages.clear
      get_replies(msg('!start'))
      chan.messages.grep(/Player order is: (.*)/) { |msg| @order = Regexp.last_match(1).split(', ') }
      chan.messages.clear
      # Unfortunate. But game_of from PMs needs this.
      @game = plugin.instance_variable_get('@games')['#test']
    end

    it 'runs through an all-nein game' do
      allow(plugin).to receive(:game_of).and_return(@game)
      allow(chan).to receive(:moderated=)
      allow(chan).to receive(:devoice)

      30.times {
        pres = @order.first

        get_replies(msg("!chancellor #{@order.last}", nick: pres))
        expect(chan.messages).to be_all { |x| x.include?('selected Chancellor') }
        chan.messages.clear

        # Until cinch-test's double-PM bug is fixed, this may emit some errors.
        # That's OK.
        players.each { |p| get_replies(pm('!nein', nick: p)) }
        expect(chan.messages).to be_any { |x| x.include?('rejected') }

        break if chan.messages.any? { |x| x.include?('have prevailed') }

        chan.messages.clear

        @order.rotate!
      }
    end
  end
end

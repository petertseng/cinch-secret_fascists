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
  def voiced
    []
  end
end

def get_replies_text(m)
  replies = get_replies(m)
  # If you wanted, you could read all the messages as they come, but that might be a bit much.
  # You'd want to check the messages of user1, user2, and chan as well.
  # replies.each { |x| puts(x.text) }
  replies.map(&:text)
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

  def authed_msg(text, nick: players[0], channel: channel1)
    m = msg(text, nick: nick, channel: channel)
    allow(m.user).to receive(:authed?).and_return(true)
    allow(m.user).to receive(:authname).and_return(nick)
    m
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

    it 'rejects public votes' do
      pres = @order.first
      get_replies(msg("!chancellor #{@order.last}", nick: pres))
      expect(get_replies_text(msg('!nein', nick: pres))).to be_all { |x| x.include?('MUST vote privately') }
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

    context 'after a policy enacted' do
      before(:each) do
        allow(plugin).to receive(:game_of).and_return(@game)
        pres = @order.first
        chanc = @order.last

        get_replies(msg("!chancellor #{chanc}", nick: pres))
        chan.messages.clear

        # Until cinch-test's double-PM bug is fixed, this may emit some errors.
        # That's OK.
        players.each { |p| get_replies(pm('!ja', nick: p)) }
        expect(chan.messages).to be_any { |x| x.include?('elected') }
        chan.messages.clear

        # TODO: Expect pres to get policy cards privately
        get_replies(msg('!discard1', nick: pres))
        expect(chan.messages).to be_all { |x| x.include?('discards one policy') }
        chan.messages.clear

        # TODO: Expect chanc to get policy cards privately
        get_replies(msg('!discard1', nick: chanc))
        expect(chan.messages).to be_any { |x| x.include?('discards one policy') }
      end

      describe 'history' do
        it 'tells history' do
          expect(get_replies_text(msg('!history'))).to be_all { |x| x.include?('Round 1') }
        end
      end

      describe 'round history' do
        it 'tells history of previous' do
          expect(get_replies_text(msg('!history 1'))).to be_all { |x| x.include?('Round 1 Election 1') }
        end

        it 'says no elections yet on current' do
          expect(get_replies_text(msg('!history 2'))).to be_all { |x| x =~ /candidates/i }
        end

        it 'rejects invalid round' do
          expect(get_replies_text(msg('!history 3'))).to be_all { |x| x =~ /invalid/i }
        end
      end

      describe 'peek' do
        it 'shows discarded card history to a non-playing mod' do
          replies = get_replies_text(authed_msg("!peek #{channel1}", nick: npmod))
          expect(replies).to_not be_empty
          expect(replies).to be_any { |x| x =~ /discarded (Fascist|Liberal)/ }
        end
      end
    end

    describe 'choices' do
      it 'shows choices for pres' do
        choices = get_replies_text(msg('!choices', nick: @order.first))
        expect(choices).to_not be_empty
        expect(choices.first).to_not include("don't need to make")
      end

      it 'shows no choices for non-pres' do
        expect(get_replies_text(msg('!choices', nick: @order.last))).to be == [
          "You don't need to make any choices right now."
        ]
      end
    end

    describe 'whoami' do
      it 'tells p1 characters' do
        expect(get_replies_text(msg('!me'))).to_not be_empty
      end
    end

    describe 'table' do
      it 'shows the table' do
        expect(get_replies_text(msg('!table'))).to_not be_empty
      end
    end

    describe 'status' do
      it 'shows the status' do
        expect(get_replies_text(msg('!status'))).to_not be_empty
      end
    end

    describe 'reset' do
      it 'lets a mod reset' do
        chan.messages.clear
        get_replies_text(authed_msg('!reset', nick: players[0]))
        expect(chan.messages).to be_any { |x| x.include?('Liberals were') }
        expect(chan.messages).to be_any { |x| x.include?('Fascists were') }
      end

      it 'does not respond to a non-mod' do
        chan.messages.clear
        get_replies_text(authed_msg('!reset', nick: players[1]))
        expect(chan.messages).to be_empty
      end
    end

    describe 'peek' do
      it 'calls a playing mod a cheater' do
        expect(get_replies_text(authed_msg('!peek', nick: players[0]))).to be == ['Cheater!!!']
      end

      it 'does not respond to a non-mod' do
        expect(get_replies_text(authed_msg('!peek', nick: players[1]))).to be_empty
      end

      it 'shows info to a non-playing mod' do
        replies = get_replies_text(authed_msg("!peek #{channel1}", nick: npmod))
        expect(replies).to_not be_empty
        expect(replies).to_not be_any { |x| x =~ /cheater/i }
        expect(replies).to be_any { |x| x.include?('Liberals were') }
        expect(replies).to be_any { |x| x.include?('Fascists were') }
      end
    end
  end

  describe 'get_settings' do
    it '!settings shows settings' do
      replies = get_replies_text(msg('!settings'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('leader name')
    end
  end

  describe 'set_settings' do
    it '!settings Darth Vader sets name' do
      replies = get_replies_text(msg('!settings Darth Vader'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('Darth Vader')
    end

    it '!settings with long name is rejected' do
      limit = described_class::FASCIST_LEADER_LIMIT
      replies = get_replies_text(msg("!settings #{?a * (limit + 1)}"))
      expect(replies).to_not be_empty
      expect(replies.first).to include('too long')
    end
  end

  describe 'help' do
    let(:help_replies) {
      get_replies_text(make_message(bot, '!help', nick: players[0]))
    }

    it 'responds to !help' do
      expect(help_replies).to_not be_empty
    end

    it 'responds differently to !help 2' do
      replies2 = get_replies_text(make_message(bot, '!help 2', nick: players[0]))
      expect(replies2).to_not be_empty
      expect(help_replies).to_not be == replies2
    end

    it 'responds differently to !help 3' do
      replies3 = get_replies_text(make_message(bot, '!help 3', nick: players[0]))
      expect(replies3).to_not be_empty
      expect(help_replies).to_not be == replies3
    end

    it 'responds differently to !help mod from a mod' do
      replies_mod = get_replies_text(authed_msg('!help mod', nick: players[0]))
      expect(replies_mod).to_not be_empty
      expect(help_replies).to_not be == replies_mod
    end

    it 'responds like !help to !help mod from a non-mod' do
      replies_normal = get_replies_text(authed_msg('!help', nick: players[1]))
      replies_mod2 = get_replies_text(authed_msg('!help mod', nick: players[1]))
      expect(replies_mod2).to_not be_empty
      expect(replies_normal).to be == replies_mod2
    end
  end

  describe 'rules' do
    it 'responds to !rules' do
      expect(get_replies_text(make_message(bot, '!rules', nick: players[0]))).to_not be_empty
    end
  end
end

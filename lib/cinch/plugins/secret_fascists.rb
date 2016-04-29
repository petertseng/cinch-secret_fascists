require 'cinch'
require 'cinch/plugins/game_bot'
require 'secret_fascists/game'
require 'secret_fascists/observer/text'

module Cinch; module Plugins; class SecretFascists < GameBot
  include Cinch::Plugin

  match(/choices/i, method: :choices, group: :secret_fascists)
  match(/me\s*$/i, method: :whoami, group: :secret_fascists)
  match(/whoami/i, method: :whoami, group: :secret_fascists)
  match(/table(?:\s+(##?\w+))?/i, method: :table, group: :secret_fascists)

  match(/history\s*$/i, method: :history, group: :secret_fascists)
  match(/history\s*(\d+)/i, method: :history_one, group: :secret_fascists)

  match(/help(?: (.+))?/i, method: :help, group: :secret_fascists)
  match(/rules/i, method: :rules, group: :secret_fascists)

  match(/settings(?:\s+(##?\w+))?$/i, method: :get_settings, group: :secret_fascists)
  match(/settings(?:\s+(##?\w+))? (.+)$/i, method: :set_settings, group: :secret_fascists)

  match(/peek(?:\s+(##?\w+))?/i, method: :peek, group: :secret_fascists)

  match(/(\S+)(?:\s+(.*))?/, method: :secret_fascists, group: :secret_fascists)

  add_common_commands

  IGNORED_COMMANDS = COMMON_COMMANDS.dup.freeze
  FASCIST_LEADER_LIMIT = 24

  class ChannelObserver < ::SecretFascists::Observer::Text
    def initialize(plugin, channel, *args)
      super(*args)
      @plugin = plugin
      @channel = channel
    end

    def public_message(msg)
      @channel.send(msg)
    end

    def private_message(player, msg)
      player.user.send(msg)
    end

    def player_removed_from_game(player)
      @plugin.user_removed_from_game(player.user, @channel)
    end
  end

  #--------------------------------------------------------------------------------
  # Implementing classes should override these
  #--------------------------------------------------------------------------------

  def min_players; ::SecretFascists::Game::MIN_PLAYERS end
  def max_players; ::SecretFascists::Game::MAX_PLAYERS end
  def game_name; ::SecretFascists::Game::GAME_NAME end

  def do_start_game(m, channel_name, players, settings, start_args)
    begin
      if (name = settings[:fascist_leader_name] || config[:default_fascist_leader_name])
        observer = ChannelObserver.new(self, Channel(channel_name), name)
      else
        observer = ChannelObserver.new(self, Channel(channel_name))
      end
      game = ::SecretFascists::Game.new(channel_name, players.map(&:user), subscribers: [observer])
    rescue => e
      m.reply("Failed to start game because #{e}", true)
      return
    end

    # Tell everyone of their initial stuff
    game.users.each { |user| tell_role(game, user: user) }

    announce_decision(game)
    game
  end

  def do_reset_game(game)
    channel = Channel(game.channel_name)
    channel.send(all_roles(game))
    channel.send(game_history(game, show_secrets: true))
  end

  def do_replace_user(game, replaced_user, replacing_user)
    tell_role(game, user: replacing_user)
  end

  def game_status(game)
    decision_info(game)
  end

  #--------------------------------------------------------------------------------
  # Other player management
  #--------------------------------------------------------------------------------

  def user_removed_from_game(user, channel)
    channel.devoice(user)
    @user_games.delete(user)
  end

  def tell_role(game, user: nil, player: nil)
    player ||= game.find_player(user)
    user ||= player.user

    info = case player.role
    when :liberal
      'You are a member of the Liberals.'
    when :fascist
      others = game.fascists - [player]
      others_info = others.empty? ? '' : " Your fellow Fascists are: #{others.join(', ')}."
      leader_info = " You are led by #{leader_name(game.channel_name)} #{game.fascist_leader}."
      "You are a member of the Fascists.#{others_info}#{leader_info}"
    when :fascist_leader
      other_info = game.fascist_leader_sees_fascists? ? " Your loyal Fascist member is #{game.fascists.join(', ')}." : " There are #{game.fascists.size} Fascists, but you do not know who they are."
      "You are #{leader_name(game.channel_name)}!#{other_info}"
    end
    user.send("Game #{game.id}: #{info}")
  end

  #--------------------------------------------------------------------------------
  # Game
  #--------------------------------------------------------------------------------

  def leader_name(channel_name)
    waiting_room = @waiting_rooms[channel_name]
    (waiting_room && waiting_room.settings[:fascist_leader_name]) || config[:default_fascist_leader_name]
  end

  def announce_decision(game)
    game.choice_names.keys.each { |p|
      explanations = game.choice_explanations(p)
      send_choice_explanations(explanations, p)
    }
  end

  def secret_fascists(m, command, args = '')
    # Don't invoke secret_fascists catchall for !who, for example.
    return if IGNORED_COMMANDS.include?(command.downcase)

    game = self.game_of(m)
    return unless game && game.users.include?(m.user)

    voted = false
    if (command.downcase == 'ja' || command.downcase == 'nein')
      if m.channel
        m.reply("You MUST vote privately. Please send me a private vote with /msg #{m.bot.nick} ja or /msg #{m.bot.nick} nein", true)
        return
      end
      voted = true
    end

    args = args ? args.split : []
    old_type = game.decision_type
    success, error = game.take_choice(m.user, command, *args)

    if success
      if voted
        # the game doesn't ack the votes, we'll ack.
        m.user.send("You voted #{command.upcase} for President #{voted_election.president} and Chancellor #{voted_election.chancellor}.")
      end

      if game.winning_party
        channel = Channel(game.channel_name)
        channel.send(all_roles(game))
        channel.send(game_history(game, show_secrets: true))
        self.start_new_game(game)
      else
        new_type = game.decision_type
        announce_decision(game) if new_type != old_type
      end
    else
      m.reply(error, true)
    end
  end

  def choices(m)
    game = self.game_of(m)
    return unless game && game.users.include?(m.user)
    explanations = game.choice_explanations(m.user)
    if explanations.empty?
      m.user.send("You don't need to make any choices right now.")
    else
      send_choice_explanations(explanations, m.user)
    end
  end

  def whoami(m)
    game = self.game_of(m)
    return unless game && game.users.include?(m.user)
    tell_role(game, user: m.user)
  end

  def next_fascist_power(game)
    next_power = ::SecretFascists::Game.fascist_power(game.original_size, game.fascist_policies + 1)
    return 'No power' unless next_power
    power_info = ::SecretFascists::Game::POWERS[next_power]
    return "Unknown power #{next_power}" unless power_info
    power_info[:name]
  end

  def table(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see a game', '!table'])
    return unless game

    info = "Liberal policies enacted: #{game.liberal_policies}. Fascist policies enacted: #{game.fascist_policies}. Next fascist power: #{next_fascist_power(game)}.\n" +
      "Policies remaining: #{game.policy_deck_size}. Policies discarded: #{game.discards_size}."
    m.reply(info)
  end

  def history(m)
    game = self.game_of(m)
    return unless game
    m.reply(game_history(game))
  end

  def history_one(m, round)
    game = self.game_of(m)
    return unless game

    round = round.to_i - 1
    if round < 0 || round >= game.current_round.id
      m.reply("Invalid round, need a number between 1 and #{game.current_round.id}", true)
      return
    end

    round_info = game.rounds[round]
    if round_info.elections.empty?
      m.reply("Round #{round_info.id}: Candidates #{round_info.candidates.map { |p| dehighlight_player(p) }.join(', ')}. No elections yet.")
      return
    end

    round_info.elections.each { |election|
      m.reply("Round #{round_info.id} Election #{election.id}: President #{dehighlight_player(election.president)} and Chancellor #{dehighlight_player(election.chancellor)}")
      if election.voting_complete?
        votes = election.votes
        jas = ::SecretFascists::Observer::Text.format_voters(votes[:ja], 'JA') { |p| dehighlight_player(p) }
        neins = ::SecretFascists::Observer::Text.format_voters(votes[:nein], 'NEIN') { |p| dehighlight_player(p) }
        m.reply("Round #{round_info.id} Election #{election.id}: #{jas}. #{neins}.")
      else
        m.reply("Round #{round_info.id} Election #{election.id}: Voting underway.")
      end
    }
  end

  def peek(m, channel_name = nil)
    return unless self.is_mod?(m.user)
    game = self.game_of(m, channel_name, ['peek', '!peek'])
    return unless game

    if game.users.include?(m.user)
      m.user.send('Cheater!!!')
      return
    end

    m.user.send(all_roles(game))
    m.user.send(game_history(game, show_secrets: true))
  end

  #--------------------------------------------------------------------------------
  # Help for player/table info
  #--------------------------------------------------------------------------------

  def dehighlight_player(p)
    dehighlight_nick(p.user.nick)
  end

  def all_roles(game)
    "The Liberals were: #{game.liberals.join(", ")}.\n" +
      "The Fascists were: #{game.fascists.join(", ")}, led by #{leader_name(game.channel_name)} #{game.fascist_leader}."
  end

  def game_history(game, show_secrets: false)
    game.rounds.map { |round|
      text = "Round #{round.id}: "
      if round.populace_enacted
        text << "Frustrated populace enacted a #{round.populace_enacted.capitalize} policy."
      elsif round.legislature_enacted
        # probably temporary. Just paranoid that this will fail.
        begin
          legislature = round.last_legislature
          if show_secrets
            text << "President #{dehighlight_player(legislature.president)} discarded #{legislature.president_discard.capitalize}, Chancellor #{dehighlight_player(legislature.chancellor)} discarded #{legislature.chancellor_discard.capitalize} and enacted a #{legislature.enacted.capitalize} policy."
          else
            text << "President #{dehighlight_player(legislature.president)} and Chancellor #{dehighlight_player(legislature.chancellor)} enacted a #{legislature.enacted.capitalize} policy."
          end
        rescue => e
          "Error: #{e}"
        end
      else
        text << "No policy enacted yet."
      end
    }.join("\n")
  end

  def send_choice_explanations(explanations, user)
    user.send('Valid choices: ' + explanations.map { |label, info|
      text = label.dup
      text << ' target' if info[:requires_args]
      text = "[#{text}: #{info[:description]}]" if info[:description]
      text
    }.join(', '))
  end

  def decision_info(game, show_choices: false)
    # TODO: Maybe some way to clean up.
    desc = case game.decision_type.first
    when :pick_chancellor; 'President must pick a Chancellor'
    when :vote; "Vote on President #{dehighlight_player(game.decision_type[1])} and Chancellor #{dehighlight_player(game.decision_type[2])}"
    when :president_cards; 'President must discard policy'
    when :chancellor_cards; 'Chancellor must discard policy'
    when :veto; 'President must accept or reject veto'
    when :investigate; 'President must Investigate'
    when :special_election; 'President must call Special Election'
    when :execute; 'President must Execute'
    else; "Unknown type #{game.decision_type}"
    end
    players = game.decision_type.first == :vote ? game.not_yet_voted : game.choice_names.keys
    choices = show_choices ? " to pick between #{game.choice_names.values.flatten.uniq.join(', ')}" : ''
    "Game #{game.id} Round #{game.current_round.id} - #{desc} - Waiting on #{players.join(', ')}#{choices}"
  end

  #--------------------------------------------------------------------------------
  # Settings
  #--------------------------------------------------------------------------------

  def get_settings(m, channel_name = nil)
    game = self.game_of(m, channel_name)
    waiting_room = self.waiting_room_of(m, channel_name || game && game.channel_name, ['see settings', '!settings'])
    return unless waiting_room
    m.reply("Fascist leader name: #{waiting_room.settings[:fascist_leader_name] || config[:default_fascist_leader_name]}")
  end

  def set_settings(m, channel_name = nil, spec = '')
    # If a game is going on, it can only be changed by people in it.
    game = self.game_of(m, channel_name)
    return if game && !game.users.include?(m.user)

    # Otherwise, anyone can change.
    waiting_room = self.waiting_room_of(m, (channel_name || game && game.channel_name), ['change settings', '!settings'])
    return unless waiting_room

    if spec.size > FASCIST_LEADER_LIMIT
      m.reply("Sorry, name too long. Limit is #{FASCIST_LEADER_LIMIT}.", true)
      return
    end

    waiting_room.settings[:fascist_leader_name] = spec
    m.reply("Fascist leader name changed to: #{spec}")
    Channel(waiting_room.channel_name).send("#{m.user} changed the Fascist leader name to #{spec}.") unless m.channel
  end

  #--------------------------------------------------------------------------------
  # General
  #--------------------------------------------------------------------------------

  def help(m, page = '')
    page ||= ''
    page = '' if page.strip.downcase == 'mod' && !self.is_mod?(m.user)
    case page.strip.downcase
    when 'mod'
      m.reply('Cheating: peek')
      m.reply('Game admin: kick, reset, replace')
    when '2'
      m.reply('Game commands: who (seating order), status (whose move is it?), table (policy card counts)')
      m.reply('Game commands: history (all rounds), history N (history for a specific round)')
      m.reply('Game commands: me (your role), choices (your current choices)')
    when '3'
      m.reply('Change Fascist leader name: settings New Name Here')
      m.reply('Getting people to play: invite, subscribe, unsubscribe')
      m.reply('To get PRIVMSG: notice off. To get NOTICE: notice on')
    else
      m.reply("General help: All commands can be issued by '!command' or '#{m.bot.nick}: command' or PMing 'command'")
      m.reply('General commands: join, leave, start')
      m.reply('Game-related commands: help 2. Preferences: help 3')
    end
  end

  def rules(m)
    m.reply('https://dl.dropboxusercontent.com/u/502769/Secret_Hitler_Rules.pdf')
  end
end; end; end

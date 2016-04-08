# cinch-secret_fascists

This is an IRC bot using [cinch](https://github.com/cinchrb/cinch), [cinch-game-bot](https://github.com/petertseng/cinch-game-bot), and [secret_fascists](https://github.com/petertseng/secret_fascists) to allow play-by-IRC of "Secret Fascists" by Max Temkin:

https://boardgamegeek.com/boardgame/188834/

[![Build Status](https://travis-ci.org/petertseng/cinch-secret_fascists.svg?branch=master)](https://travis-ci.org/petertseng/cinch-secret_fascists)

The astute will note that this is not the actual name of the game.
Fortunately, that does not really matter, as the name of the Fascist leader is configurable per game.

## Setup

You'll need a recent version of [Ruby](https://www.ruby-lang.org/).
Ruby 2.1 or newer is required because of required keyword arguments.
The [build status](https://travis-ci.org/petertseng/cinch-secret_fascists) will confirm compatibility with various Ruby versions.
Note that [2.1 is in security maintenance mode](https://www.ruby-lang.org/en/news/2016/02/24/support-plan-of-ruby-2-0-0-and-2-1/), so it would be better to use a later version.

You'll need to install the required gems, which can be done automatically via `bundle install`, or manually by reading the `Gemfile` and using `gem install` on each gem listed.

## Usage

Given that you have performed the requisite setup, the minimal code to get a working bot might resemble:

```ruby
require 'cinch'
require 'cinch/plugins/secret_fascists'

bot = Cinch::Bot.new do
  configure do |c|
    c.nick            = 'SecretFascistsBot'
    c.server          = 'irc.example.org'
    c.channels        = ['#playsecretfascists']
    c.plugins.plugins = [Cinch::Plugins::SecretFascists]
    c.plugins.options[Cinch::Plugins::SecretFascists] = {
      channels: ['#playsecretfascists'],
      settings: 'secretfascists-settings.yaml',
    }
  end
end

bot.start
```

## Configuration

Along with the standard configuration options of [cinch-game_bot](https://github.com/petertseng/cinch-game_bot), this plugin supports the following plugin-specific configuration options:

* `default_fascist_leader_name`: The default name of the leader of the Fascist (informed minority) team.

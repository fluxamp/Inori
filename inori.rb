#!/usr/bin/env ruby

abort 'ERROR: MumbleBot requires Ruby version 2.0 or greater to run.' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0')

# irc communication
require 'cinch'
require 'cinch/log_filter'
# config file
require 'yaml'

require_relative 'mumblebot/bot'
require_relative 'mumblebot/plugins'

begin
  CONFIG = YAML.load_file('config.yml') unless defined? CONFIG
rescue Errno::ENOENT
  abort 'ERROR: config.yml not found. Copy, edit and rename config-sample.yml if this has not yet been done.'
end

# TODO: make volume persistent
class Inori_mumble < MumbleBot::MumbleBot
  include Cinch::Plugin

  listen_to :connect, method: :join_mumble

  match /pause/, method: :on_pause
  match /resume/, method: :on_resume
  match /volume ([0-9]+)/, method: :on_volume

  timer CONFIG['plugin-update-rate'], method: :timer_loop, start_automatically: false

  def initialize(m)
    super

    debug 'initialize mumble plugin'
    mb = MumbleBot::MumbleBot.instance_method(:initialize)
    mb.bind(self).call(nil, CONFIG['mumble'])
    debug 'called MumbleBot.initialize'
  end

  # irc callbacks
  def on_pause(m)
    @mpd.pause = true
  end

  def on_resume(m)
    @mpd.pause = false
  end

  def on_volume(m, v)
    vol = v.to_i
    if vol >= 0 && vol <= 100
      @mumble.player.volume = vol
    end
  end

  # mumble functions
  def on_song_change(song=nil)
    # "next song: \"#{song.title}\", requested by #{song.albumartist}"
  end

  def join_mumble(m)
    # setup mumble part of the bot
    @mumble.connect

    @mumble.on_connected do
      setup
      configure_plugins(@plugins)
      @timers.each do |t|
        t.start
      end

      @mpd.on :song, &method(:on_song_change)
    end
  end

  def timer_loop
    MumbleBot::Plugin.tick(self, @plugins)
  end
end

class PingPongFilter < Cinch::LogFilter
  # filter out PING/PONG log messages
  def filter(message, event)
    if event == :incoming && message.include?('PONG')
      return nil
    elsif event == :outgoing && message.include?('PING')
      return nil
    end

    message
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.nick = CONFIG['irc']['nick']
    c.realname = CONFIG['irc']['user']
    c.user = CONFIG['irc']['user']
    c.server = CONFIG['irc']['server']
    c.channels = CONFIG['irc']['channels']
    c.port = CONFIG['irc']['port']
    c.ssl.use = true

    c.plugins.plugins = [Inori_mumble]
  end

  @loggers.filters << PingPongFilter.new()
end

begin
    bot.start
rescue SystemExit, Interrupt
    bot.quit
end

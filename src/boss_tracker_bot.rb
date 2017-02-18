require 'discordrb'
require_relative 'boss_tracker'

PREFIX = ENV['PREFIX'] || '!'
COMMANDS = {
  help: {
    description: "Get you some help"
  },
  kill: {
    description: "Marks the boss as killed and starts a new timer"
  },
  next: {
    min_args: 1,
    max_args: 3,
    description: "Sets the next boss time. Usage: '#{PREFIX}next 5:15:12'",
    usage: 'h:mm:ss   (eg: "4:15:23" or "21:15")'
  },
  history: {
    description: "Show the kill history"
  },
  level: {
    min_args: 0,
    max_args: 1,
    description: "Get and set the current boss level",
    usage: "level [###]"
  },
  timer: {
    description: "Display the next boss time"
  }
}

class BossTrackerBot
  attr_reader :bot, :boss_tracker

  MIN_LEVEL = 1
  MAX_LEVEL = 999

  TIME_REGEX = /
    \A
    (?:
      (?:(?<h>\d)h)?           # match 5h 15m 23s format
      (?:(?<m>\d{1,2})m)?
      (?:(?<s>\d{1,2})s)
    |
      (?:(?<h>\d)[\.:])?       # match 5:15:23 format
      (?:(?<m>\d{1,2})[\.:])?
      (?:(?<s>\d{1,2}))
    )
    \z
  /x

  def initialize
    @bot = Discordrb::Commands::CommandBot.new({
      token: ENV['BOT_TOKEN'],
      client_id: ENV['CLIENT_ID'],
      prefix: PREFIX,
      channels: [ENV['BOSS_CHANNEL_ID'].to_i],
    })
    @bot.bucket(:boss, limit: 10, time_span: 30, delay: 2)

    setup_commands

    puts("Invite at #{bot.invite_url}")
    @boss_tracker = BossTracker.new(bot)
  end

  def run
    run_tracker
    run_bot
  end

  private

  #### COMMANDS ####

  def help(event, _)
    event << '```js'
    l = COMMANDS.keys.map(&:size).max

    COMMANDS.each do |command, args|
      next if command == :help || !args[:description]

      event << "#{PREFIX}%-#{l}s - #{args[:description]}" % command
    end
    event << '```'
  end

  def kill(*)
    boss_tracker.kill
  end

  def next(event, args)
    parsed_time = parse_time(args)

    if parsed_time
      boss_tracker.set_next(parsed_time)
      event << "Boss time updated"
    else
      event << "Incorrect params. Correct usage is:"
      event << "`#{set_next_usage}`"
    end
  end

  def history(*)
    boss_tracker.print_history
  end

  def level(event, args)
    curr_level = args.first
    if curr_level
      curr_level = curr_level.to_i
      if curr_level < MIN_LEVEL || curr_level > MAX_LEVEL
        event << "Given level must be a valid number"
      else
        boss_tracker.set_level(curr_level)
      end
    else
      boss_tracker.print_level
    end
  end

  def timer(*)
    boss_tracker.print_timer
  end

  #### UTILITY ####

  def setup_commands
    COMMANDS.each do |command, options|
      bot.command(command, options.merge(default_options)) do |event, *args|
        send(command, event, args)
      end
    end
  end

  def parse_time(time_array)
    match = TIME_REGEX.match(time_array.join.gsub(/\s/, ''))
    return unless match

    result = {}
    result[:hour] = match[:h].to_i if match[:h]
    result[:minute] = match[:m].to_i if match[:m]
    result[:second] = match[:s].to_i

    result
  end

  def default_options
    {bucket: :boss}
  end

  def run_tracker
    Thread.new do
      loop do
        begin
          loop do
            boss_tracker.tick
            sleep 0.5
          end
        rescue => e
          puts("Uncaught exception: #{e}")
        end
      end
    end
  end

  def run_bot
    loop do
      begin
        bot.run
      rescue => e
        puts("Uncaught exception: #{e}")
      end
    end
  end
end

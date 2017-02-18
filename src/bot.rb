require 'discordrb'
require_relative 'boss_tracker'

PREFIX = ENV['PREFIX'] || '!'
MIN_LEVEL = 1
MAX_LEVEL = 999

bot = Discordrb::Commands::CommandBot.new({
  token: ENV['BOT_TOKEN'],
  client_id: ENV['CLIENT_ID'],
  prefix: PREFIX,
  channels: [ENV['BOSS_CHANNEL_ID'].to_i],
})

puts("Invite at #{bot.invite_url}")
boss_tracker = BossTracker.new(bot)

bot.bucket :boss, limit: 10, time_span: 30, delay: 2

args = {
  description: "Get you some help",
  bucket: :boss
}
bot.command(:help, args) do |event|
  event << '```js'
  event << "#{PREFIX}kill    - Marks the boss as killed and starts a new timer"
  event << "#{PREFIX}next    - Sets the next boss time. Usage: '#{PREFIX}next 5:15:12'"
  event << "#{PREFIX}history - Displays the kill history"
  event << "#{PREFIX}level   - Get and set the current boss level"
  event << "#{PREFIX}timer   - Display the next boss time"
  event << '```'
end

args = {
  description: "Marks the boss as killed and starts a new timer",
  bucket: :boss
}
bot.command(:kill, args) do |event|
  boss_tracker.kill(event)
end

set_next_usage = 'h:mm:ss   (eg: "4:15:23" or "21:15")'
args = {
  min_args: 1,
  max_args: 3,
  description: "Sets the next boss time",
  usage: set_next_usage,
  bucket: :boss
}
bot.command(:next, args) do |event, *args|
  parsed_time = parse_time(args)

  if parsed_time
    boss_tracker.set_next(event, parsed_time)
    event << "Boss time updated"
  else
    event << "Incorrect params. Correct usage is:"
    event << "`#{set_next_usage}`"
  end
end

args = {
  description: "Show the kill history",
  bucket: :boss
}
bot.command(:history, args) do |event|
  boss_tracker.print_history(event)
end

args = {
  min_args: 0,
  max_args: 1,
  description: "Get and set the current boss level",
  usage: "level [###]",
  bucket: :boss
}
bot.command(:level, args) do |event, level|
  if level
    level = level.to_i
    if level < MIN_LEVEL || level > MAX_LEVEL
      event << "Given level must be a valid number"
    else
      boss_tracker.set_level(event, level)
    end
  else
    boss_tracker.print_level(event)
  end
end

args = {
  description: "Display the next boss time",
  bucket: :boss
}
bot.command(:timer, args) do |event|
  boss_tracker.print_timer(event)
end

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

def parse_time(time_array)
  match = TIME_REGEX.match(time_array.join.gsub(/\s/, ''))
  return unless match

  result = {}
  result[:hour] = match[:h].to_i if match[:h]
  result[:minute] = match[:m].to_i if match[:m]
  result[:second] = match[:s].to_i

  result
end

Thread.new do
  loop do
    begin
      boss_tracker.run
    rescue => e
      puts("Uncaught exception: #{e}")
    end
  end
end

loop do
  begin
    bot.run
  rescue => e
    puts("Uncaught exception: #{e}")
  end
end

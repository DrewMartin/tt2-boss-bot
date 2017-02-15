require 'discordrb'
require 'dotenv'
require_relative 'boss_timer'

Dotenv.load

PREFIX = ENV['PREFIX'] || '!'
MIN_LEVEL = 1
MAX_LEVEL = 999

bot = Discordrb::Commands::CommandBot.new({
  token: ENV['BOT_TOKEN'],
  client_id: ENV['CLIENT_ID'],
  prefix: PREFIX,
  channels: [ENV['BOSS_CHANNEL_ID'].to_i],
})
puts bot.invite_url
boss_timer = BossTimer.new(bot)

bot.bucket :boss, limit: 10, time_span: 30, delay: 2

args = {
  description: "Marks the boss as killed and starts a new timer",
  bucket: :boss
}
bot.command(:kill, args) do |event|
  boss_timer.kill(event)
end

set_next_usage = '[##h] [##m] ##s   (eg: "5h 25m 15s" or "50s")'
args = {
  min_args: 1,
  max_args: 3,
  description: "Sets the next boss time",
  usage: set_next_usage,
  bucket: :boss
}
bot.command(:set_next, args) do |event, *args|
  parsed_time = parse_time(args)

  if parsed_time
    boss_timer.set_next(event, parsed_time)
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
  boss_timer.print_history(event)
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
      boss_timer.set_level(event, level)
    end
  else
    boss_timer.print_level(event)
  end
end

TIME_REGEX = /\A(?:(?<h>\d)h)?(?:(?<m>\d{1,2})m)?(?:(?<s>\d{1,2})s)?\z/

def parse_time(time_array)
  match = TIME_REGEX.match(time_array.join.gsub(/\s/, ''))
  return unless match
  return unless match[:h] || match[:m] || match[:s]

  result = {}
  result[:hour] = match[:h].to_i if match[:h]
  result[:minute] = match[:m].to_i if match[:m]
  result[:second] = match[:s].to_i if match[:s]

  result
end

Thread.new do
  loop do
    begin
      boss_timer.run
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

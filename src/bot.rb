require 'discordrb'
require 'dotenv'
require_relative 'boss_timer'

Dotenv.load

PREFIX = '!'
puts("BOT_TOKEN #{ENV['BOT_TOKEN']} CLIENT_ID #{ENV['CLIENT_ID']} BOSS_CHANNEL_ID #{ENV['BOSS_CHANNEL_ID'].to_i}")

bot = Discordrb::Commands::CommandBot.new({
  token: ENV['BOT_TOKEN'],
  client_id: ENV['CLIENT_ID'],
  prefix: PREFIX,
  channels: [ENV['BOSS_CHANNEL_ID'].to_i],
})



boss_timer = BossTimer.new(bot)

bot.bucket :boss, limit: 10, time_span: 30, delay: 2

# bot.command(:help, bucket: :boss) do |event|
#   event << "```js"
#   event << "'what' - the fuck"
#   event << "'is' - this shit"
#   event << "```"
# end

bot.command(:kill,
  description: "Marks the boss as killed and starts a new timer",
  bucket: :boss) do |event|
  boss_timer.kill(event)
end

set_next_usage = '[##h] [##m] ##s   (eg: "5h 25m 15s" or "50s")'
bot.command(:set_next,
  min_args: 1,
  max_args: 3,
  description: "Sets the next boss time",
  usage: set_next_usage,
  bucket: :boss) do |event, *args|
  parsed_time = parse_time(args)

  if parsed_time
    boss_timer.set_next(parsed_time)
    event << "Boss time updated"
  else
    event << "Incorrect params. Correct usage is:"
    event << "`#{set_next_usage}`"
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
  begin
    boss_timer.run
  rescue => e
    puts("Uncaught exception: #{e}")
  end
end

bot.run

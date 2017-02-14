require 'discordrb'

token = ENV['BOT_TOKEN'] || "FAKE"
bot = Discordrb::Bot.new token: token, client_id: 280889496340398080

bot.message(content: 'what') do
  "That's what I thought"
end

bot.run

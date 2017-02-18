require 'dotenv'

if ENV['TEST']
  Dotenv.load('.env.test', '.env.test.local')
else
  Dotenv.load
end

REQUIRED_ENVS = %w(DATABASE_URL BOT_TOKEN CLIENT_ID BOSS_CHANNEL_ID)
missing_envs = REQUIRED_ENVS - ENV.keys

unless missing_envs.empty?
  puts("Missing env keys: #{missing_envs.join(', ')}")
  exit 1
end

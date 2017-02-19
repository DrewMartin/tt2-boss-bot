require 'dotenv'
require 'rubygems'
require 'active_support'
require 'active_support/core_ext'
require 'data_mapper'
require 'discordrb'

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

log_level = ENV['LOG_LEVEL']&.to_sym || :info
DataMapper::Logger.new($stdout, log_level)
DataMapper.setup(:default, ENV['DATABASE_URL'])
DataMapper::Model.raise_on_save_failure = true

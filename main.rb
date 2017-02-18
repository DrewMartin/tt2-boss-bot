lib_dir = File.expand_path('lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'config'
require_relative 'src/boss_tracker_bot'

BossTrackerBot.new.run

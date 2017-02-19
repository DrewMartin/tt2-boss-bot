ENV['TEST'] = '1'
$VERBOSE=nil

require 'config'
require 'active_support/testing/autorun'
require 'minitest/pride'
require 'mocha/mini_test'
require 'timecop'
require 'byebug'
require 'using_db'
ActiveSupport.test_order = :random

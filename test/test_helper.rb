ENV['TEST'] = '1'

require 'config'
require 'active_support/testing/autorun'
require 'minitest/pride'
require 'mocha/mini_test'
require 'timecop'
require 'byebug'
ActiveSupport.test_order = :random

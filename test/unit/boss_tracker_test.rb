require "test_helper"
require_relative "../../src/boss_tracker"

class FakeMessage
  attr_accessor :content
  attr_accessor :author

  def initialize(content)
    self.content = content
  end

  def pin; end
  def unpin; end
  def edit; end
end

class FakeChannel
  attr_reader :channel_id

  def initialize(channel_id)
    @channel_id = channel_id
  end

  def send_message(message)
  end
end

class FakeBot
  def channel(channel_id)
    FakeChannel.new(channel_id)
  end

  def current_bot?
    true
  end
end

class BossTrackerTest < Minitest::Test
  def setup
    @bot = FakeBot.new
    @boss_tracker = BossTracker.new(@bot)
  end

  def test_during_setup_message_sent_to_channel
    channel = FakeChannel.new(123456)
    @bot.expects(:channel).with(ENV['BOSS_CHANNEL_ID'].to_i).returns(channel)
    channel.expects(:send_message).with("I'm alive")
    BossTracker.new(@bot)
  end

  def test_set_level_updates_the_clan_level_and_prints_it
    expected_msg = "Clan level is 50 with a bonus of 11.64K%"
    expect_message(expected_msg)
    @boss_tracker.set_level(50)

    assert_equal 50, @boss_tracker.level
  end

  def test_print_level_sends_unknown_level_message_if_level_not_set
    expected_msg = "Clan level is unknown"
    expect_message(expected_msg)

    @boss_tracker.print_level
  end

  def test_set_level_updates_the_clan_level_and_prints_it
    @boss_tracker.set_level(230)

    expected_msg = "Clan level is 230 with a bonus of 82.08B%"
    expect_message(expected_msg)

    @boss_tracker.print_level
  end

  def test_set_next_without_a_boss_time_sets_one_and_updates_history
    assert_nil @boss_tracker.next_boss_at
    assert_equal [], @boss_tracker.history

    Timecop.freeze do
      @boss_tracker.set_next(hour: 3, minute: 15, second: 12)
      next_boss_at = Time.now + ((3 * 60) + 15) * 60 + 12
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal [last_death_at], @boss_tracker.history
      assert_equal next_boss_at, @boss_tracker.next_boss_at
    end
  end

  def test_set_next_with_a_future_boss_time_updates_history
    Timecop.freeze do
      @boss_tracker.set_next(hour: 3, minute: 15, second: 12)

      next_boss_at = Time.now + ((3 * 60) + 15) * 60 + 12
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal [last_death_at], @boss_tracker.history
      assert_equal next_boss_at, @boss_tracker.next_boss_at

      @boss_tracker.set_next(hour: 2, minute: 45, second: 32)
      next_boss_at = Time.now + ((2 * 60) + 45) * 60 + 32
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal [last_death_at], @boss_tracker.history
      assert_equal next_boss_at, @boss_tracker.next_boss_at
    end
  end

  def test_set_next_with_a_past_boss_time_treats_it_as_a_kill
    now = Time.now
    expected_history = []
    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12
      @boss_tracker.set_next(second: 12)

      assert_equal expected_history, @boss_tracker.history
    end

    Timecop.freeze(now + 120) do
      assert_equal Time.now - 108, @boss_tracker.next_boss_at
      expect_message('Boss killed in 1m 28s.')

      @boss_tracker.set_next(second: BossTracker::BOSS_DELAY - 20)

      expected_history << Time.now - 20
      assert_equal expected_history, @boss_tracker.history
    end
  end

  def test_set_next_with_a_past_boss_time_treats_it_as_a_kill_with_level_set
    now = Time.now
    expected_history = []
    @boss_tracker.set_level(10)

    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12
      @boss_tracker.set_next(second: 12)

      assert_equal expected_history, @boss_tracker.history
    end

    Timecop.freeze(now + 120) do
      assert_equal Time.now - 108, @boss_tracker.next_boss_at
      expect_message("Clan level is 11 with a bonus of 185.31%")
      expect_message('Boss killed in 1m 28s.')

      @boss_tracker.set_next(second: BossTracker::BOSS_DELAY - 20)

      expected_history << Time.now - 20
      assert_equal expected_history, @boss_tracker.history
      assert_equal 11, @boss_tracker.level
    end
  end

  def test_kill_does_not_modify_level_if_not_set
    assert_nil @boss_tracker.level
    @boss_tracker.kill

    assert_nil @boss_tracker.level
  end

  def test_kill_increments_level_then_prints_it_and_updates_history_and_next_boss_time
    assert_equal [], @boss_tracker.history
    assert_nil @boss_tracker.next_boss_at
    @boss_tracker.set_level(5)

    expected_msg = "Clan level is 6 with a bonus of 77.16%"
    expect_message(expected_msg)

    Timecop.freeze do
      @boss_tracker.kill

      assert_equal 6, @boss_tracker.level
      assert_equal [Time.now], @boss_tracker.history
      assert_equal Time.now + BossTracker::BOSS_DELAY, @boss_tracker.next_boss_at
    end
  end

  def test_kill_prints_kill_time_and_updates_history_if_previous_time_is_set
    expected_history = []
    now = Time.now
    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12
      @boss_tracker.set_next(second: 12)
    end

    Timecop.freeze(now + 120) do
      assert_equal Time.now - 108, @boss_tracker.next_boss_at
      expect_message('Boss killed in 1m 48s.')

      @boss_tracker.kill

      expected_history << Time.now
      assert_equal expected_history, @boss_tracker.history
    end
  end

  def test_kill_prints_an_error_and_nothing_else_if_boss_time_is_in_the_future
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_level(150)
      @boss_tracker.set_next(second: 12)

      expect_message("You're not fighting a boss yet")
      @boss_tracker.kill

      assert_equal [now - BossTracker::BOSS_DELAY + 12], @boss_tracker.history
      assert_equal 150, @boss_tracker.level
    end
  end

  def test_print_history_displays_nothing_if_no_history
    expect_message("No history recorded").twice
    @boss_tracker.print_history

    @boss_tracker.set_next(second: 10)
    @boss_tracker.print_history
  end

  def test_print_history_displays_the_current_boss_history
    now = Time.now
    @boss_tracker.set_level(150)
    Timecop.freeze(now) { @boss_tracker.set_next(second: 10) }
    Timecop.freeze(now += 150) { @boss_tracker.kill }
    Timecop.freeze(now += BossTracker::BOSS_DELAY + 3830) { @boss_tracker.kill }
    Timecop.freeze(now += BossTracker::BOSS_DELAY + 15) { @boss_tracker.kill }

    expected_msg = [
      '```js',
      'Boss 150 - 2m 20s',
      'Boss 151 - 1h 3m 50s',
      'Boss 152 - 15s',
      '```'
    ].join("\n")
    expect_message(expected_msg)

    @boss_tracker.print_history
  end

  def test_print_timer_shows_an_error_if_no_next_boss_time
    assert_nil @boss_tracker.next_boss_at
    expect_message("Next boss time is unknown.")

    @boss_tracker.print_timer
  end

  def test_print_timer_shows_in_progress_if_next_boss_time_in_the_past
    @boss_tracker.set_next(second: 10)
    Timecop.travel(20)
    expect_message("Boss fight in progress")

    @boss_tracker.print_timer
  end

  def test_print_timer_shows_the_boss_time_if_it_is_in_the_future_and_pins_the_message
    Timecop.freeze do
      @boss_tracker.set_next(second: 10)
      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end
  end

  def test_print_timer_unpins_the_previous_boss_message
    message = nil
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(second: 10)
      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end

    Timecop.freeze(now + 5) do
      message.expects(:unpin)

      message = generate_bot_message("Next boss in 5s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end
  end

  def test_tick_does_nothing_if_next_boss_time_is_not_set
    @boss_tracker.channel.expects(:send_message).never

    @boss_tracker.tick
  end

  def test_tick_does_nothing_if_next_boss_time_is_in_the_past
    @boss_tracker.set_next(second: 10)
    Timecop.travel(20)
    @boss_tracker.channel.expects(:send_message).never

    @boss_tracker.tick
  end

  def test_tick_creates_a_boss_message_if_there_is_none_and_next_boss_time_set
    Timecop.freeze do
      @boss_tracker.set_next(second: 10)
      assert_nil @boss_tracker.boss_message


      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
    end
  end

  def test_tick_updates_previous_message_if_it_is_set_but_not_too_frequently
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(hour: 1, minute: 5, second: 20)
      assert_nil @boss_tracker.boss_message

      message = generate_bot_message("Next boss in 1h 5m 20s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
      assert_equal message, @boss_tracker.boss_message
    end

    Timecop.freeze(now += 65) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1h 4m 15s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 1) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).never

      @boss_tracker.tick
    end

    Timecop.freeze(now + 4) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1h 4m 10s")

      @boss_tracker.tick
    end
  end

  def test_tick_sends_alerts_to_the_channel_when_close_to_the_boss
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(minute: 16)
      assert_nil @boss_tracker.boss_message

      message = generate_bot_message("Next boss in 16m 0s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
      assert_equal message, @boss_tracker.boss_message
    end

    Timecop.freeze(now += 70) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 14m 50s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 14m 50s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 90) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 13m 20s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 500) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 5m 0s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 5m 0s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 60) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 4m 0s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 125) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 1m 55s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1m 55s")

      @boss_tracker.tick
    end
  end

  private

  def generate_bot_message(text)
    message = FakeMessage.new(text)
    message.author = @bot
    message
  end

  def expect_message(text, message: nil)
    @boss_tracker.channel.expects(:send_message).with(text)
  end

  def boss_channel
    @bot.instance_variable_get(:@channel)
  end
end

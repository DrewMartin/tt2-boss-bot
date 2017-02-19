require "test_helper"
require_relative "../../src/boss_tracker"

class FakeMessage
  attr_reader :content, :id, :author

  def initialize(content:, id:, author:)
    @content = content
    @id = id
    @author = author
  end

  def pin; end
  def unpin; end

  def edit(text)
    @content = content
  end
end

class FakeChannel
  attr_reader :id

  def initialize(id)
    @id = id
  end

  def send_message(message)
  end
end

class FakeBot
  attr_reader :token

  def initialize(token)
    @token = token
  end

  def channel(channel_id)
    FakeChannel.new(channel_id)
  end

  def current_bot?
    true
  end
end

class BossTrackerTest < ActiveSupport::TestCase
  include UsingDb

  setup do
    @bot = FakeBot.new('fake')
    @boss_tracker = BossTracker.new(@bot)
  end

  test "during setup message sent to channel" do
    channel = FakeChannel.new(123456)
    @bot.expects(:channel).with(ENV['BOSS_CHANNEL_ID']).returns(channel)
    channel.expects(:send_message).with("I'm alive")
    BossTracker.new(@bot)
  end

  test "during setup the old boss message is unpinned" do
    Clan.update(boss_message_id: 'asdf')
    Discordrb::API::Channel.expects(:unpin_message).with('fake', ENV['BOSS_CHANNEL_ID'], 'asdf')

    BossTracker.new(@bot)
  end

  test "during setup level and next_boss time are loaded from the db" do
    now = Time.now
    Clan.update(next_boss: now, level: 147)

    boss_tracker = BossTracker.new(@bot)
    assert_equal 147, boss_tracker.level
    assert_equal now.to_s, boss_tracker.next_boss_at.to_time.to_s
  end

  test "#set_level updates the clan level and prints it" do
    expected_msg = "Clan level is 50 with a bonus of 11.64K%"
    expect_message(expected_msg)
    @boss_tracker.set_level(50)

    assert_equal 50, @boss_tracker.level
    assert_equal 50, Clan.first.level
  end

  test "#set_level updates the last boss kill's level" do
    kill = @boss_tracker.clan.boss_kills.create(killed_at: Time.now - 5.hours)
    @boss_tracker.set_level(50)

    assert_equal 49, kill.reload.level

    @boss_tracker.set_level(123)

    assert_equal 122, kill.reload.level
  end

  test "#print_level sends unknown level message if the level is not set" do
    expected_msg = "Clan level is unknown"
    expect_message(expected_msg)

    @boss_tracker.print_level
  end

  test "#print_level prints the clan level if there is one" do
    @boss_tracker.set_level(230)

    expected_msg = "Clan level is 230 with a bonus of 82.08B%"
    expect_message(expected_msg)

    @boss_tracker.print_level
  end

  test "#set_next without a boss time sets one and updates kill history" do
    assert_nil @boss_tracker.next_boss_at
    assert_equal 0, @boss_tracker.clan.boss_kills.size

    Timecop.freeze do
      delta = 3.hours + 15.minutes + 12.seconds
      @boss_tracker.set_next(delta)
      next_boss_at = Time.now + delta
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal_history([last_death_at])
      assert_equal next_boss_at, @boss_tracker.next_boss_at
    end
  end

  test "#set_next with a future boss time updates history" do
    Timecop.freeze do
      delta = 3.hours + 15.minutes + 12.seconds
      @boss_tracker.set_next(delta)

      next_boss_at = Time.now + delta
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal_history([last_death_at])
      assert_equal next_boss_at, @boss_tracker.next_boss_at

      delta = 2.hours + 45.minutes + 32.seconds
      @boss_tracker.set_next(delta)
      next_boss_at = Time.now + delta
      last_death_at = next_boss_at - BossTracker::BOSS_DELAY
      assert_equal_history([last_death_at])
      assert_equal next_boss_at, @boss_tracker.next_boss_at
    end
  end

  test "#set_next with a past boss time treats it as a kill" do
    now = Time.now
    expected_history = []
    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12.seconds
      @boss_tracker.set_next(12.seconds)

      assert_equal_history(expected_history)
    end

    Timecop.freeze(now + 2.minutes) do
      assert_equal Time.now - 2.minutes + 12.seconds, @boss_tracker.next_boss_at
      expect_message('Boss killed in 1m 28s.')

      @boss_tracker.set_next(BossTracker::BOSS_DELAY - 20.seconds)

      expected_history << Time.now - 20.seconds
      assert_equal_history(expected_history)
    end
  end

  test "#set_next with a past boss time treats it as a kill (with level set)" do
    now = Time.now
    expected_history = []
    @boss_tracker.set_level(10)

    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12.seconds
      @boss_tracker.set_next(12.seconds)

      assert_equal_history(expected_history)
    end

    Timecop.freeze(now + 2.minutes) do
      assert_equal Time.now - 2.minutes + 12.seconds, @boss_tracker.next_boss_at
      expect_message("Clan level is 11 with a bonus of 185.31%")
      expect_message('Boss killed in 1m 28s.')

      @boss_tracker.set_next(BossTracker::BOSS_DELAY - 20.seconds)

      expected_history << Time.now - 20.seconds
      assert_equal_history(expected_history)
      assert_equal 11, @boss_tracker.level
    end
  end

  test "#kill does not modify level if not set" do
    assert_nil @boss_tracker.level
    @boss_tracker.kill

    assert_nil @boss_tracker.level
  end

  test "#kill increments level then prints it and updates history and next boss time" do
    assert_equal 0, @boss_tracker.clan.boss_kills.size
    assert_nil @boss_tracker.next_boss_at
    @boss_tracker.set_level(5)

    expected_msg = "Clan level is 6 with a bonus of 77.16%"
    expect_message(expected_msg)

    Timecop.freeze do
      @boss_tracker.kill

      assert_equal 6, @boss_tracker.level
      assert_equal_history([Time.now])
      assert_equal Time.now + BossTracker::BOSS_DELAY, @boss_tracker.next_boss_at
    end
  end

  test "#kill prints kill time and updates history if previous time is set" do
    expected_history = []
    now = Time.now
    Timecop.freeze(now) do
      expected_history << now - BossTracker::BOSS_DELAY + 12.seconds
      @boss_tracker.set_next(12)
    end

    Timecop.freeze(now + 2.minutes) do
      assert_equal Time.now - 2.minutes + 12.seconds, @boss_tracker.next_boss_at
      expect_message('Boss killed in 1m 48s.')

      @boss_tracker.kill

      expected_history << Time.now
      assert_equal_history(expected_history)
    end
  end

  test "#kill prints an error and nothing else if the boss time is in the future" do
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_level(150)
      @boss_tracker.set_next(12.seconds)

      expect_message("You're not fighting a boss yet")
      @boss_tracker.kill

      assert_equal_history([now - BossTracker::BOSS_DELAY + 12.seconds])
      assert_equal 150, @boss_tracker.level
    end
  end

  test "#print_history displays nothing if there's no history" do
    expect_message("No history recorded").twice
    @boss_tracker.print_history

    @boss_tracker.set_next(10.seconds)
    @boss_tracker.print_history
  end

  test "#print_history displays the current boss history" do
    now = Time.now
    @boss_tracker.set_level(150)

    Timecop.freeze(now) { @boss_tracker.set_next(10.seconds) }
    Timecop.freeze(now += 2.minutes + 30.seconds) { @boss_tracker.kill }
    Timecop.freeze(now += BossTracker::BOSS_DELAY + 1.hour + 3.minutes + 50.seconds) { @boss_tracker.kill }
    Timecop.freeze(now += BossTracker::BOSS_DELAY + 15.seconds) { @boss_tracker.kill }

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

  test "#print_timer shows an error if there's no next boss time" do
    assert_nil @boss_tracker.next_boss_at
    expect_message("Next boss time is unknown.")

    @boss_tracker.print_timer
  end

  test "#print_timer shows in progress if the next boss time in the past" do
    @boss_tracker.set_next(10.seconds)
    Timecop.travel(20.seconds)
    expect_message("Boss fight in progress")

    @boss_tracker.print_timer
  end

  test "#print_timer shows the boss time if it is in the future, and pins the message" do
    Timecop.freeze do
      @boss_tracker.set_next(10.seconds)
      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end
  end

  test "#print_timer unpins the previous boss message" do
    message = nil
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(10.seconds)
      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end

    Timecop.freeze(now + 5.seconds) do
      message.expects(:unpin)

      message = generate_bot_message("Next boss in 5s")
      message.expects(:pin)
      expect_message(message.content).returns(message)

      @boss_tracker.print_timer
    end
  end

  test "#tick does nothing if next boss time is not set" do
    @boss_tracker.channel.expects(:send_message).never

    @boss_tracker.tick
  end

  test "#tick does nothing if next boss time is in the past" do
    @boss_tracker.set_next(10.seconds)
    Timecop.travel(20)
    @boss_tracker.channel.expects(:send_message).never

    @boss_tracker.tick
  end

  test "#tick createsa boss message if there is none and next boss time set" do
    Timecop.freeze do
      @boss_tracker.set_next(10.seconds)
      assert_nil @boss_tracker.boss_message


      message = generate_bot_message("Next boss in 10s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
    end
  end

  test "#tick updates previous message if it is set but not too frequently" do
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(1.hour + 5.minutes + 20.seconds)
      assert_nil @boss_tracker.boss_message

      message = generate_bot_message("Next boss in 1h 5m 20s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
      assert_equal message, @boss_tracker.boss_message
    end

    Timecop.freeze(now += 1.minute + 5.seconds) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1h 4m 15s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 1.second) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).never

      @boss_tracker.tick
    end

    Timecop.freeze(now + 4.seconds) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1h 4m 10s")

      @boss_tracker.tick
    end
  end

  test "#tick sends alerts to the channel when close to the boss" do
    now = Time.now
    Timecop.freeze(now) do
      @boss_tracker.set_next(16.minutes)
      assert_nil @boss_tracker.boss_message

      message = generate_bot_message("Next boss in 16m 0s")
      message.expects(:pin)
      message.expects(:edit).never
      expect_message(message.content).returns(message)

      @boss_tracker.tick
      assert_equal message, @boss_tracker.boss_message
    end

    Timecop.freeze(now += 1.minute + 10.seconds) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 14m 50s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 14m 50s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 1.minute + 30.seconds) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 13m 20s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 8.minutes + 20.seconds) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 5m 0s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 5m 0s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 1.minute) do
      @boss_tracker.channel.expects(:send_message).never
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 4m 0s")

      @boss_tracker.tick
    end

    Timecop.freeze(now += 2.minutes + 5.seconds) do
      @boss_tracker.channel.expects(:send_message).with("@everyone Next boss in 1m 55s")
      @boss_tracker.boss_message.expects(:edit).with("Next boss in 1m 55s")

      @boss_tracker.tick
    end
  end

  private

  def assert_equal_history(times)
    history = @boss_tracker.clan.boss_kills.map {|k| k.killed_at.to_time.to_s}
    assert_equal times.map(&:to_s), history
  end

  def generate_bot_message(text)
    id = (Random.rand * 1**32).round
    FakeMessage.new(content: text, author: @bot, id: id.to_s)
  end

  def expect_message(text, message: nil)
    @boss_tracker.channel.expects(:send_message).with(text)
  end

  def boss_channel
    @bot.instance_variable_get(:@channel)
  end
end

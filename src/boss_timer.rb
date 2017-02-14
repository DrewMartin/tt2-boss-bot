class BossTimer
  NEXT_BOSS_KEY = 'next_boss'

  ALERT_TIMES = [10 * 60, 2 * 60, 1 * 60].freeze

  def initialize(bot)
    @bot = bot
    @channel = bot.channel(ENV['BOSS_CHANNEL_ID'].to_i)
  end

  def run
    loop do
      boss_tick
      sleep 2
    end
  end

  def kill(event)
    set_next_boss_time(time(hour: 6))
    clear_boss_message
  end

  def set_next(time_struct)
    set_next_boss_time(time(time_struct))
  end

  private
  attr_reader :bot,
              :next_boss_at,
              :channel,
              :boss_message,
              :alert_times

  def time(hour: 0, minute: 0, second: 0)
    (hour * 60 + minute) * 60 + second
  end

  def etl_string(time)
    delta = (time - Time.now).to_i

    strings = []
    strings.unshift "#{delta % 60}s"
    delta /= 60

    if delta > 0
      strings.unshift "#{delta % 60}m"
      delta /= 60
      strings.unshift "#{delta}h" if delta > 0
    end

    strings.join(' ')
  end

  def set_next_boss_time(seconds)
    clear_boss_message
    @next_boss_at = Time.now.utc + seconds
  end

  def boss_tick
    return unless next_boss_at && next_boss_at > Time.now

    if boss_message
      update_boss_message
    else
      create_boss_message
    end
  end

  def update_boss_message
    boss_message.edit(generate_boss_message)
    boss_alert_channel
  end

  def boss_alert_channel
    return unless alert_times && !alert_times.empty? && next_boss_at
    delta  = (next_boss_at - Time.now).to_i
    next_alert = nil

    while !alert_times.empty? && delta <= alert_times.first do
      next_alert = alert_times.shift
    end
    return unless next_alert

    minutes = next_alert / 60
    channel.send_message("@everyone Next boss in #{minutes} minute#{'s' if minutes > 1}")
  end

  def create_boss_message
    # Clear old pins
    old_pins = @channel.pins.select do |m|
      m.author.current_bot? && m.content =~ /\ANext boss in/
    end

    old_pins.each(&:unpin)

    @boss_message = channel.send_message(generate_boss_message)
    @boss_message.pin
    @alert_times = ALERT_TIMES.dup
  end

  def clear_boss_message
    return unless boss_message
    boss_message.unpin
    @boss_message = nil
  end

  def generate_boss_message
    "Next boss in #{etl_string(next_boss_at)}"
  end
end

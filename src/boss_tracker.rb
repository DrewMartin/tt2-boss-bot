class BossTracker
  NEXT_BOSS_KEY = 'next_boss'

  SUFFIXES = %w(K M B T aa ab ac ad ae)
  ALERT_TIMES = [15 * 60, 5 * 60, 2 * 60].freeze
  BOSS_DELAY = 6 * 60 * 60
  UPDATE_DELAY = 2
  HISTORY_SIZE = 10

  attr_reader :channel,
              :level,
              :history,
              :bot,
              :next_boss_at,
              :boss_message,
              :alert_times

  def initialize(bot)
    @bot = bot
    @channel = bot.channel(ENV['BOSS_CHANNEL_ID'].to_i)
    @channel.send_message("I'm alive")
    @history = []
  end

  def tick
    return unless next_boss_at && next_boss_at > Time.now

    if boss_message
      update_boss_message
    else
      create_boss_message
    end
  end

  def set_level(level)
    @level = level
    print_level
  end

  def print_level
    channel.send_message(clan_bonus_message)
  end

  def set_next(time_struct)
    if next_boss_at && next_boss_at < Time.now
      record_boss_kill(Time.now + time(time_struct) - BOSS_DELAY)
      set_level(level + 1) if level
      print_lass_boss_kill_time
    else
      record_boss_kill(Time.now + time(time_struct) - BOSS_DELAY, replace_last: true)
      print_lass_boss_kill_time(with_level: false)
    end
    set_next_boss_time(time(time_struct))
  end

  def kill
    if next_boss_at && next_boss_at > Time.now
      channel.send_message("You're not fighting a boss yet")
      return
    end
    set_level(level + 1) if level
    record_boss_kill(Time.now)
    set_next_boss_time(time(second: BOSS_DELAY))
    print_lass_boss_kill_time
    clear_boss_message
  end

  def print_history
    return channel.send_message("No history recorded") if history.size < 2

    message = []
    message << '```js'
    history.each.with_index do |time, i|
      next if i == 0
      boss_num = if level
        level - history.size + i
      else
        i
      end
      boss_time = (time - history[i-1] - BOSS_DELAY).round
      message << "Boss %3d - #{time_delta_string(boss_time)}" % boss_num
    end
    message << '```'
    channel.send_message(message.join("\n"))
  end

  def print_timer
    if next_boss_at
      if next_boss_at > Time.now
        create_boss_message
      else
        channel.send_message("Boss fight in progress")
      end
    else
      channel.send_message("Next boss time is unknown.")
    end
    return
  end

  private

  def time(hour: 0, minute: 0, second: 0)
    (hour * 60 + minute) * 60 + second
  end

  def etl_string(time)
    delta = (time - Time.now).to_i
    time_delta_string(delta)
  end

  def time_delta_string(delta)
    strings = []
    strings.unshift "%ds" % (delta % 60)
    delta /= 60

    if delta > 0
      strings.unshift "%dm" % (delta % 60)
      delta /= 60
      strings.unshift "#{delta}h" if delta > 0
    end

    strings.join(' ').strip
  end

  def clan_bonus_message
    return "Clan level is unknown" unless level
    "Clan level is #{level} with a bonus of #{boss_bonus_string}"
  end

  def boss_bonus_string
    return "unknown" unless level

    level_calc = level
    bonus = 1
    if level_calc > 200
      bonus *= 1.05 ** (level_calc - 200)
      level_calc = 200
    end

    bonus *= 1.1 ** level_calc
    bonus -= 1
    bonus *= 100

    number_with_suffix(bonus) + "%"
  end

  def number_with_suffix(number)
    suffix_pos = -1
    while number > 1000 && suffix_pos < SUFFIXES.size - 1
      suffix_pos += 1
      number /= 1000.0
    end

    result = "%.2f" % number
    result += SUFFIXES[suffix_pos] if suffix_pos >= 0

    result
  end

  def set_next_boss_time(seconds)
    clear_boss_message
    @next_boss_at = Time.now.utc + seconds
  end

  def update_boss_message
    now = Time.now
    return if @last_updated_at && @last_updated_at + UPDATE_DELAY > now
    @last_updated_at = now
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

    channel.send_message("@everyone Next boss in #{etl_string(next_boss_at)}")
  end

  def create_boss_message
    # Clear old pinned message
    boss_message&.unpin

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

  def record_boss_kill(killed_at, replace_last: false)
    if replace_last
      history.pop
      history.push(killed_at)
    else
      history.push(killed_at)
      @history = history.last(HISTORY_SIZE + 1) if history.size > HISTORY_SIZE + 1
    end
  end

  def print_lass_boss_kill_time(with_level: true)
    return unless history.size > 1
    boss_time = (history[-1] - history[-2] - BOSS_DELAY).round
    channel.send_message("Boss killed in #{time_delta_string(boss_time)}.")
  end
end

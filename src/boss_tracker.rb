require_relative 'clan'
require_relative 'boss_kill'
DataMapper.auto_upgrade!

class BossTracker
  NEXT_BOSS_KEY = 'next_boss'

  SUFFIXES = %w(K M B T aa ab ac ad ae)
  ALERT_TIMES = [15.minutes, 5.minutes, 2.minutes].freeze
  BOSS_DELAY = 6.hours
  UPDATE_DELAY = 4.seconds
  CHIRP_DELAY = 5.minutes
  PREFIX = ENV['PREFIX'] || '!'
  CHIRPS = [
    "What the hell? It's taking you %s to beat the boss??",
    "Ok surely someone forgot to tell me the boss is dead right? It's been %s. Use '#{PREFIX}kill' or '#{PREFIX}next H:MM:SS' to let me know it's dead.",
    "Ok this is just sad. It's been %s and the boss is still alive.",
    "@everyone should be ashamed of themselves. %s and the boss is still alive."
  ].freeze

  attr_reader :channel,
              :level,
              :bot,
              :next_boss_at,
              :boss_message,
              :alert_times,
              :clan

  def initialize(bot)
    @bot = bot
    channel = ENV['BOSS_CHANNEL_ID']
    @channel = bot.channel(channel)
    @clan = Clan.first_or_create(channel_id: channel)
    load_from_clan if clan.saved?

    @channel.send_message("I'm alive")
  end

  def reload
    @clan = Clan.first(channel_id: @channel.id)
    load_from_clan
    @boss_message = nil
    @next_chirp_at = nil
    @chirp_index = 0
  end

  def tick
    return unless next_boss_at

    if next_boss_at < Time.now
      chirp
    elsif boss_message
      update_boss_message
    else
      create_boss_message
    end
  end

  def chirp
    if @next_chirp_at.nil?
      @next_chirp_at = next_boss_at + CHIRP_DELAY
      @chirp_index = 0
    end

    if @next_chirp_at <= Time.now
      @next_chirp_at = Time.now + CHIRP_DELAY
      message = CHIRPS[@chirp_index] % time_delta_string(Time.now.to_i - next_boss_at.to_i)
      channel.send_message(message)
      @chirp_index = (@chirp_index + 1) % CHIRPS.size
    end
  end

  def set_level(level)
    update_level(level)
    if (kill = clan.boss_kills.last) && kill.level != level - 1
      kill.update(level: level - 1)
    end
  end

  def print_level
    channel.send_message(clan_bonus_message)
  end

  def set_next(seconds)
    if next_boss_at && next_boss_at < Time.now
      increment_level
      record_boss_kill(Time.now + seconds - BOSS_DELAY)
      print_lass_boss_kill_time
    else
      record_boss_kill(Time.now + seconds - BOSS_DELAY, replace_last: true)
      reload
      print_lass_boss_kill_time(with_level: false)
    end
    set_next_boss_time(seconds)
  end

  def kill
    if next_boss_at && next_boss_at > Time.now
      channel.send_message("You're not fighting a boss yet")
      return
    end
    increment_level
    record_boss_kill(Time.now)
    set_next_boss_time(BOSS_DELAY)
    print_lass_boss_kill_time
    clear_boss_message
  end

  def print_history
    history = clan.kill_history.reverse
    return channel.send_message("No history recorded") if history.size < 2

    message = []
    message << '```js'
    history.each.with_index do |kill, i|
      next if i == 0
      boss_num = kill.level || i
      boss_time = (kill.killed_at.to_i - history[i-1].killed_at.to_i - BOSS_DELAY).round
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

  def load_from_clan
    return unless clan.saved?
    if clan.boss_message_id
      Discordrb::API::Channel.unpin_message(bot.token, channel.id, clan.boss_message_id)
    end

    @next_boss_at = clan.next_boss.to_time if clan.next_boss
    @level = clan.level if clan.level
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
    @next_boss_at = Time.now + seconds
    clan.update(next_boss: @next_boss_at)
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
    boss_message&.unpin

    @boss_message = channel.send_message(generate_boss_message)
    @boss_message.pin
    clan.update(boss_message_id: @boss_message.id)

    time_to_boss = next_boss_at - Time.now
    @alert_times = ALERT_TIMES.select { |t| t < time_to_boss || t == ALERT_TIMES.last }
    @next_chirp_at = nil
  end

  def clear_boss_message
    return unless boss_message
    boss_message.unpin
    @boss_message = nil
    clan.update(boss_message_id: nil)
  end

  def generate_boss_message
    "Next boss in #{etl_string(next_boss_at)}"
  end

  def record_boss_kill(killed_at, replace_last: false)
    kill_record = nil
    kill_record = clan.boss_kills.last if replace_last
    kill_record ||= clan.boss_kills.new

    kill_record.killed_at = killed_at
    kill_record.level = level - 1 if level
    kill_record.save
  end

  def print_lass_boss_kill_time(with_level: true)
    history = clan.boss_kills.all(limit: 2)
    return unless history.size > 1
    boss_time = (history[0].killed_at.to_i - history[1].killed_at.to_i - BOSS_DELAY).round
    channel.send_message("Boss killed in #{time_delta_string(boss_time)}.")
  end

  def increment_level
    return unless level
    update_level(level + 1)
  end

  def update_level(level)
    @level = level
    clan.update(level: level)
    print_level
  end

end

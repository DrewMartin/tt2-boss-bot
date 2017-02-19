class Clan
  include DataMapper::Resource

  HISTORY_SIZE = 10

  property :id,               Serial    # An auto-increment integer key
  property :level,            Integer   # Current clan level
  property :next_boss,        DateTime  # Time of the next boss
  property :boss_message_id,  String    # Discord id of the current pinned boss messsage
  property :channel_id,       String, required: true, unique: true # Discord id of the channel to watch/talk in

  has n, :boss_kills, order: [:id.desc]

  def initialize(*args)
    @level = @next_boss = @channel_id = @id = @boss_message_id = nil
    super(*args)
  end

  def kill_history
    boss_kills.all(limit: HISTORY_SIZE + 1)
  end
end

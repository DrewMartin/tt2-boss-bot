class BossKill
  include DataMapper::Resource

  property :id,         Serial    # An auto-increment integer key
  property :level,      Integer   # Boss level at this kill
  property :killed_at,  DateTime, required: true # Time the boss was killed

  belongs_to :clan
end

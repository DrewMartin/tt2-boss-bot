module UsingDb
  def before_setup
    @_db_wiper_transaction = DataMapper::Transaction.new(DataMapper::Model.descendants.to_a)
    @_db_wiper_transaction.begin

    @_db_wiper_adapters = DataMapper::Model.descendants.flat_map do |m|
      m.repositories.map(&:adapter)
    end
    @_db_wiper_adapters.each {|a| a.push_transaction(@_db_wiper_transaction)}
    super
  end

  def after_teardown
    super
  ensure
    @_db_wiper_adapters.each(&:pop_transaction)
    @_db_wiper_transaction.rollback
  end
end

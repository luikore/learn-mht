# frozen_string_literal: true

class AdvisoryLock
  def self.with_transaction_lock(lock_name)
    lock_id = Zlib.crc32(lock_name.to_s)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_id})")
      yield
    end
  end
end

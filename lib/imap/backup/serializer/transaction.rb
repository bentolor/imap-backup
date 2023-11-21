module Imap; end

module Imap::Backup
  # Stores data during a transaction
  class Serializer::Transaction
    attr_reader :data

    def initialize(owner:)
      @data = nil
      @owner = owner
      @in_transaction = false
    end

    # Runs the transaction
    def begin(data, &block)
      @data = data
      @in_transaction = true
      block.call
      @in_transaction = false
    end

    # Clears rollback data
    def clear
      @data = nil
    end

    def in_transaction?
      @in_transaction
    end

    # Throws an exception if there is a current transaction
    def fail_in_transaction!(method, message: "not supported inside trasactions")
      raise "#{owner.class}##{method} #{message}" if in_transaction?
    end

    # Throws an exception if there is not a current transaction
    def fail_outside_transaction!(method)
      raise "#{owner.class}##{method} can only be called inside a transaction" if !in_transaction?
    end

    private

    attr_reader :owner
  end
end

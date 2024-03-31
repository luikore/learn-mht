# frozen_string_literal: true

module Digest
  class Keccak256
    def self.digest(data)
      Digest::Keccak.digest(data, 256).unpack("H*").first
    end
  end
end

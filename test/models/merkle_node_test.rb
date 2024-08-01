# frozen_string_literal: true

require "test_helper"

# XXX: skip event callbacks
class Event
  def add_to_merkle_tree
  end
end

class MerkleNodeTest < ActiveSupport::TestCase
  class IdentityDigest
    def self.digest(s)
      # Strip off the first character, it'll just be a \0 or \x1 anyway
      s[1..-1]
    end
  end

  SECP256K1 = Secp256k1::Context.create
  # Fixed seed for test
  KEY_PAIR = SECP256K1.key_pair_from_private_key(
    Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
  )
  SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)

  def push_events(start_num, end_num)
    batch = 100
    tree = nil
    (start_num..end_num).to_a.each_slice(batch) do |data_set|
      events = data_set.map do |i|
        data = i.to_s 36
        hashed_data = IdentityDigest.digest("\0" + data)
        signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
        timestamp = 1708758140 + i
        event = Event.new eid: hashed_data,
                          pubkey: SIGNER_PUBLIC_KEY,
                          kind: "CHAR",
                          topic: "CHAR",
                          session: "CHAR",
                          content: "",
                          sig: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                          created_at: timestamp
        event.save!(validate: false)
        event
      end
      tree = events.first.merkle_tree_hash
      MerkleNode.push_leaves_with_lock!(events)
      MerkleNode.untaint! tree
      puts
      puts
    end
    tree
  end

  test "consistency_proof" do
    Event.where("1=1").delete_all
    MerkleNode.where("1=1").delete_all
    MerkleNode.hasher = IdentityDigest
    tree = push_events 1, 100
    node = MerkleNode.tree_root(tree)
    push_events 101, 200
    iseq = node.consistency_proof
    stack = []
    # pp iseq
    iseq.each do |s|
      if s[:reduce] > 0
        children = stack.pop s[:reduce]
        calculated = MerkleNode.hasher.digest("\x01" + children.join)
        assert_equal s[:hash], calculated, "hash mismatch for #{s[:id]}"
      end
      stack.push s[:hash]
    end
    assert_equal 1, stack.size
  end
end

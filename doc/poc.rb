#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
CURRENT_PATH = Pathname.new File.expand_path(__dir__)

require_relative "../config/environment"

class IdentityDigest
  def self.digest(s)
    # Strip off the first character, it'll just be a \0 or \x1 anyway
    s[1..-1]
  end
end

# https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#standard-merkle-trees
def digest(m)
  IdentityDigest.digest(m)
end

def make_new_leaf(event)
  lineage = MerkleNode.push_leaves!([event])
  MerkleNode.untaint! event.session, IdentityDigest
end

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)

("A".."Z").to_a.map(&:to_s).each_with_index do |data, i|
  hashed_data = digest("\0" + data)
  signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
  timestamp = 1708758140 + i

  event = Event.create! signer: SIGNER_PUBLIC_KEY,
                        session: "CHAR",
                        data: data,
                        hashed_data: hashed_data,
                        signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                        timestamp: timestamp
  make_new_leaf(event)
end
root = MerkleNode.root("CHAR")
puts root.calculated_hash
File.write 'char.dot', root.to_dot_digraph

saved_timestamp = nil
saved_hash = nil
(1..100).to_a.map(&:to_s).each_with_index do |data, i|
  hashed_data = digest("\0" + data)
  signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
  timestamp = 1708758140 + i

  event = Event.create! signer: SIGNER_PUBLIC_KEY,
                        session: "NUMBER",
                        data: data,
                        hashed_data: hashed_data,
                        signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                        timestamp: timestamp
  make_new_leaf(event)

  if i == 20
    saved_timestamp = timestamp
    saved_hash = MerkleNode.root("NUMBER").calculated_hash
  end
end
root = MerkleNode.root("NUMBER")
puts root.calculated_hash
File.write 'number.dot', root.to_dot_digraph
puts ""

# proof
proof = MerkleNode.proof("NUMBER", saved_timestamp)
proof.each do |n|
  n.calculated_hash ||= IdentityDigest.digest "\0#{n.children.map(&:calculated_hash).join}"
end
actual_hash = proof.last.calculated_hash
puts "proof size: #{proof.size}"
puts "proof expected: #{saved_hash}"
puts "got: #{actual_hash}"
puts "match: #{actual_hash == saved_hash}"

# binding.irb

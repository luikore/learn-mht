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

MerkleNode.hasher = IdentityDigest

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)

saved_hashes = {}
("A".."Z").to_a.map(&:to_s).each_with_index do |data, i|
  # https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#standard-merkle-trees
  hashed_data = MerkleNode.hasher.digest("\0" + data)
  signature = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
  nonce = i
  timestamp = 1708758140 + i

  event = Event.create!(
    raw: data,
    raw_hash: hashed_data,
    signature: Secp256k1::Util.bin_to_hex(signature.serialized),
    timestamp: timestamp,
    session: "NUMBER",
    nonce: nonce,
    signer: SIGNER_PUBLIC_KEY
  )

  saved_hashes[nonce] = event.merkle_node.tree_root.calculated_hash
end
root = Event.where(session: "NUMBER").first.merkle_tree_root
puts "root hash: #{root.calculated_hash}"
# File.write "tmp/number.dot", root.to_dot_digraph
puts ""

# proof
Event.of_signer_and_session(SIGNER_PUBLIC_KEY, "NUMBER").each do |event|
  puts "Event nonce: #{event.nonce}"

  merkle_node = event.merkle_node
  proof = merkle_node.inclusion_proof

  puts "===="
  proof.each do |n|
    if n.event_id.present?
      puts "Event: #{n.calculated_hash}"
    else
      puts "Children(#{n.children.size}): #{n.children.map(&:calculated_hash).join(", ")} Full: #{n.full?}"
    end
  end
  puts "===="

  proof.each do |n|
    n.calculated_hash ||=
      if n.children
        MerkleNode.calculate_hash(n.children.map(&:calculated_hash).join)
      else
        event.raw_hash
      end
  end
  actual_hash = proof.last.calculated_hash
  saved_hash = saved_hashes.fetch(event.nonce)

  puts "Expected: #{saved_hash}"
  puts "Got: #{actual_hash}"
  if actual_hash == saved_hash
    puts "Verified"
  else
    raise "Proof mismatched"
  end
  puts ""
end

# binding.irb

#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
CURRENT_PATH = Pathname.new File.expand_path(__dir__)

require_relative "../config/environment"

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)[2..]

saved_hashes = {}
(1..100).to_a.map(&:to_s).each_with_index do |content, i|
  # https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#standard-merkle-trees
  timestamp = 1708758140 + i
  session = "0"
  topic = Digest::Keccak256.digest("fake")

  event = Event.new(
    kind: 1111,
    content: content,
    pubkey: SIGNER_PUBLIC_KEY,
    created_at: timestamp,
    tags: [
      ["s", session],
      ["t", topic]
    ]
  )
  event.eid = event.computed_eid
  event.sig = Secp256k1::Util.bin_to_hex(
    SECP256K1.sign_schnorr(
      KEY_PAIR,
      Digest::SHA256.digest(event.serialized_nostr_event_json)
    ).serialized
  )

  event.save!

  saved_hashes[timestamp] = event.merkle_node.tree_root.calculated_hash
end

events_scope = Event.of_topic(Digest::Keccak256.digest("fake")).of_pubkey(SIGNER_PUBLIC_KEY).of_session("0")
root = events_scope.first.merkle_tree_root
puts "root hash: #{root.calculated_hash}"
# File.write "tmp/number.dot", root.to_dot_digraph
puts ""

# proof
events_scope.each do |event|
  puts "Event id: #{event.eid}"

  merkle_node = event.merkle_node
  proof = merkle_node.inclusion_proof

  # puts "===="
  # proof.each do |n|
  #   if n.event_id.present?
  #     puts "#{n.calculate_hash} Level: #{n.level}"
  #   else
  #     puts "#{n.calculate_hash} Children(#{n.children.size}): #{n.children.map(&:calculate_hash).join(", ")}  Level: #{n.level}"
  #   end
  # end
  # puts "===="

  proof.map!(&:calculate_hash)
  # pp proof

  actual_hash = proof.last
  saved_hash = saved_hashes.fetch(event.created_at.to_i)

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

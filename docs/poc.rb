#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
CURRENT_PATH = Pathname.new File.expand_path(__dir__)

require_relative "../config/environment"

def assert(predicate)
  return if predicate
  raise RuntimeError, 'assertion failed', caller
end

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)[2..]

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
end

events_scope = Event.of_topic(Digest::Keccak256.digest("fake")).of_pubkey(SIGNER_PUBLIC_KEY).of_session("0").order(created_at: :asc)
latest_event = events_scope.last
root = latest_event.merkle_tree_root
# File.write "tmp/number.dot", root.to_dot_digraph

root_hash = root.calculated_hash
puts "root hash: #{root_hash}"
puts ""

# proof
events_scope.each do |event|
  puts "Event id: #{event.eid}"

  merkle_node = event.merkle_node
  inclusion_proof = merkle_node.inclusion_proof(latest_event)

  stack = []
  inclusion_proof.each do |elem|
    hash = elem[:hash]
    reduce = elem[:reduce]
    # is_path = elem[:is_path]
    assert(stack.size >= reduce)
    if reduce > 0
      children = stack.pop reduce
      assert(Digest::Keccak256.digest("\x01" + children.join) == hash)
    end
    stack.push hash
  end
  assert(stack.size == 1)

  if stack[0] != root_hash
    raise "Inclusion proof invalid, expect: #{root_hash}, got: #{stack[0]}"
  else
    puts "Inclusion proof verified"
  end
  puts ""
end

# binding.irb

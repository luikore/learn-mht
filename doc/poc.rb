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

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)

# def make_merkle_tree(leaves)
#   if leaves.empty?
#     raise "Expected non-zero number of leaves"
#   end
#
#   tree = Array.new(2 * leaves.length - 1)
#
#   leaves.each_with_index do |leaf, i|
#     tree[tree.size - 1 - i] = leaf
#   end
#
#   (tree.size - 1 - leaves.size).downto(0).each do |i|
#     left_child_index = 2 * i + 1
#     right_child_index = 2 * i + 2
#
#     tree[i] = "#{tree[left_child_index]}#{tree[right_child_index]}" # TODO:
#   end
#
#   tree
# end

def make_new_leaf(event)
  event_size = Event.where(signer: event.signer).size
  if event_size == 1
    MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                           session: event.session,
                           event: event
  elsif event_size == 1
    left_leaf =
      begin
        previous_event = Event.where(signer: SIGNER_PUBLIC_KEY).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data).root
      end

    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        event: event

    calculated_hash = digest("\x01" + left_leaf.calculated_hash + event.hashed_data)
    root_leaf = MerkleTreeLeaf.create! calculated_hash: calculated_hash,
                                       session: event.session,
                                       event: event

    root_leaf.append_child(left_leaf)
    root_leaf.append_child(right_leaf)
  elsif event_size.odd?
    left_leaf =
      begin
        previous_event = Event.where(signer: SIGNER_PUBLIC_KEY).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data).root
      end

    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        event: event

    left_leaf_children = left_leaf.children
    left_leaf_left_child = left_leaf_children.first
    left_leaf_right_child = left_leaf_children.last
    if left_leaf_left_child.descendants.size == left_leaf_right_child.descendants.size
      calculated_hash = digest("\x01" + left_leaf.calculated_hash + event.hashed_data)
      root_leaf = MerkleTreeLeaf.create! calculated_hash: calculated_hash,
                                         session: event.session,
                                         event: event

      root_leaf.append_child(left_leaf)
      root_leaf.append_child(right_leaf)
    else
      # If depth not the same, the right child must be the thinner one

      calculated_hash = digest("\x01" + left_leaf_right_child.calculated_hash + right_leaf.calculated_hash)
      new_left_leaf_right_child = MerkleTreeLeaf.create! parent: left_leaf,
                                                         calculated_hash: calculated_hash,
                                                         session: event.session

      new_left_leaf_right_child.append_child(left_leaf_right_child)
      new_left_leaf_right_child.append_child(right_leaf)

      calculated_hash = digest("\x01" + left_leaf_left_child.calculated_hash + new_left_leaf_right_child.calculated_hash)
      left_leaf.update! calculated_hash: calculated_hash
    end
  else # size is even
    origin_right_leaf =
      begin
        previous_event = Event.where(signer: SIGNER_PUBLIC_KEY).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data)
      end

    left_leaf = MerkleTreeLeaf.create! calculated_hash: origin_right_leaf.calculated_hash,
                                       session: origin_right_leaf.session
    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        event: event
    origin_right_leaf.append_child(left_leaf)
    origin_right_leaf.append_child(right_leaf)

    calculated_hash = digest("\x01" + origin_right_leaf.calculated_hash + event.hashed_data)
    origin_right_leaf.update! calculated_hash: calculated_hash

    root_leaf = origin_right_leaf.parent
    if root_leaf
      calculated_hash = root_leaf.children.map(&:calculated_hash).join
      root_leaf.update! calculated_hash: calculated_hash

      root_leaf = root_leaf.parent
      if root_leaf
        calculated_hash = root_leaf.children.map(&:calculated_hash).join
        root_leaf.update! calculated_hash: calculated_hash
      end
    end
  end
end

data = "A"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758135

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "B"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758136

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "C"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758137

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "D"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758138

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "E"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758139

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "F"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758140

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "G"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758141

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "H"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758142

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "I"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758143

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "J"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758144

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

data = "K"
hashed_data = digest("\0" + data)
signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
timestamp = 1708758145

event = Event.create! signer: SIGNER_PUBLIC_KEY,
                      session: "TEST",
                      data: data,
                      hashed_data: hashed_data,
                      signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                      timestamp: timestamp
make_new_leaf(event)

puts MerkleTreeLeaf.last.root.to_dot_digraph
# binding.irb

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

def make_new_leaf(event)
  # puts "--- #{event.hashed_data} ----"
  event_size = Event.where(signer: event.signer, session: event.session).size
  if event_size == 1
    MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                           session: event.session,
                           event: event

    return
  elsif event_size == 1
    left_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
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

    return
  elsif event_size.odd?
    left_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data).parent
      end

    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        event: event

    parent_leaf = left_leaf.root
    while parent_leaf
      parent_leaf_children = parent_leaf.children
      parent_leaf_left_child = parent_leaf_children.first
      parent_leaf_right_child = parent_leaf_children.last

      if parent_leaf_left_child.descendants.size == parent_leaf_right_child.descendants.size
        calculated_hash = digest("\x01" + parent_leaf.calculated_hash + event.hashed_data)
        new_parent_leaf = MerkleTreeLeaf.create! calculated_hash: calculated_hash,
                                                 session: parent_leaf.session

        if parent_leaf.parent
          parent_leaf.parent.append_child(new_parent_leaf)
        end
        parent_leaf.update! parent: new_parent_leaf
        new_parent_leaf.append_child(right_leaf)

        root_leaf = new_parent_leaf.parent
        break
      end

      parent_leaf = parent_leaf_right_child
    end
  else # size is even
    origin_right_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
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
  end

  while root_leaf do
    calculated_hash = root_leaf.children.map(&:calculated_hash).join
    root_leaf.update! calculated_hash: calculated_hash

    root_leaf = root_leaf.parent
  end
end

("A".."Z").each_with_index do |data, i|
  hashed_data = digest("\0" + data)
  signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
  timestamp = 1708758140 + i

  event = Event.create! signer: SIGNER_PUBLIC_KEY,
                        session: "TEST",
                        data: data,
                        hashed_data: hashed_data,
                        signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                        timestamp: timestamp
  make_new_leaf(event)
end

puts MerkleTreeLeaf.last.root.to_dot_digraph
# binding.irb

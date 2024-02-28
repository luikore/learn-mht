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

  # 获取总共 Event 的数量，注意此时还没有为最新的 Event 创建树叶
  event_size = Event.where(signer: event.signer, session: event.session).size
  if event_size == 1 # 当只有一个 Event 的时候
    # 当前叶子节点同时也是树根节点
    MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                           session: event.session,
                           timestamp: event.timestamp,
                           event: event

    return
  elsif event_size == 2 # 当只有两个 Event 的时候
    left_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data).root
      end

    # 直接创建右侧的叶子节点
    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        timestamp: event.timestamp,
                                        event: event

    # 创建树根节点
    calculated_hash = digest("\x01" + left_leaf.calculated_hash + event.hashed_data)
    root_leaf = MerkleTreeLeaf.create! calculated_hash: calculated_hash,
                                       session: event.session,
                                       timestamp: event.timestamp,
                                       event: event

    root_leaf.add_child(left_leaf)
    root_leaf.add_child(right_leaf)

    return
  elsif event_size.odd? # 当有奇数个 Event 的时候
    left_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data).parent
      end

    # 新添加的 Event 的叶子节点永远都在树枝的右侧
    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        timestamp: event.timestamp,
                                        event: event

    # 从树根开始遍历
    parent_leaf = left_leaf.root
    while parent_leaf
      parent_leaf_children = parent_leaf.children
      parent_leaf_left_child = parent_leaf_children.first
      parent_leaf_right_child = parent_leaf_children.last

      # 寻找树枝左右两侧的深度都相等，这个树枝是“完全的”，在这个位置插入新的 Event 的叶子节点
      if parent_leaf_left_child.descendants.size == parent_leaf_right_child.descendants.size
        parent_leaf_parent = parent_leaf.parent
        # 构造一个新的树干节点
        calculated_hash = digest("\x01" + parent_leaf.calculated_hash + right_leaf.calculated_hash)
        new_parent_leaf = MerkleTreeLeaf.create! parent: parent_leaf_parent,
                                                 calculated_hash: calculated_hash,
                                                 session: parent_leaf.session,
                                                 timestamp: parent_leaf.timestamp

        # if parent_leaf_parent
        #   l = parent_leaf_parent.children.first
        #   r = parent_leaf_parent.children.last
        #   puts "#{parent_leaf.parent.calculated_hash}: #{l.calculated_hash}(#{l.timestamp}) - #{r.calculated_hash}(#{r.timestamp})"
        # end

        # 将遍历到的树干节点和新 Event 的叶子节点挂在上边
        new_parent_leaf.add_child(parent_leaf)
        new_parent_leaf.add_child(right_leaf)

        # puts "#{new_parent_leaf.calculated_hash}: #{parent_leaf.calculated_hash} - #{right_leaf.calculated_hash}"
        # if new_parent_leaf.parent
        #   l = new_parent_leaf.parent.children.first
        #   r = new_parent_leaf.parent.children.last
        #   puts "#{new_parent_leaf.parent.calculated_hash}: #{l.calculated_hash}(#{l.timestamp}) - #{r.calculated_hash}(#{r.timestamp})"
        # end

        # 新的节点已经计算过哈希了，所以一会从新的树干节点的父节点开始遍历更新哈希
        root_leaf = new_parent_leaf.parent
        break
      end

      # 永远都是右边的叶子“不完全”，所以如果当前深度没找到，就从当前树干的右侧枝干继续往下找
      parent_leaf = parent_leaf_right_child
    end
  else # 当有偶数个 Event 的时候
    # 此时右侧的叶子一定“不完全”，所以把新的 Event 接到右边去，这时叶子节点会升格成枝干
    origin_right_leaf =
      begin
        previous_event = Event.where(signer: event.signer, session: event.session).order(timestamp: :desc).offset(1).first
        MerkleTreeLeaf.find_by!(calculated_hash: previous_event.hashed_data)
      end

    # 当前的右侧叶子节点变成枝干，所以复制当前的右侧叶子，作为新枝干的左边叶子节点
    left_leaf = MerkleTreeLeaf.create! calculated_hash: origin_right_leaf.calculated_hash,
                                       session: origin_right_leaf.session,
                                       timestamp: origin_right_leaf.timestamp
    # 当前 Event 作为右侧叶子节点
    right_leaf = MerkleTreeLeaf.create! calculated_hash: event.hashed_data,
                                        session: event.session,
                                        timestamp: event.timestamp,
                                        event: event
    # 将刚创建的左右叶子节点接到刚升格成枝干节点的原右侧叶子节点去
    origin_right_leaf.add_child(left_leaf)
    origin_right_leaf.add_child(right_leaf)

    # 更新刚升格成枝干的节点的信息
    calculated_hash = digest("\x01" + left_leaf.calculated_hash + right_leaf.calculated_hash)
    origin_right_leaf.update! calculated_hash: calculated_hash,
                              timestamp: right_leaf.timestamp

    # puts "#{origin_right_leaf.calculated_hash}: #{left_leaf.calculated_hash} - #{right_leaf.calculated_hash}"

    # 新的节点已经计算过哈希了，所以一会从新的树干节点的父节点开始遍历更新哈希
    root_leaf = origin_right_leaf.parent
  end

  # 向上遍历更新哈希
  while root_leaf do
    # l = root_leaf.children.first
    # r = root_leaf.children.last
    # puts "#{l.calculated_hash} : #{r.calculated_hash}"

    calculated_hash = root_leaf.children.map(&:calculated_hash).join
    root_leaf.update! calculated_hash: calculated_hash,
                      timestamp: root_leaf.children.map(&:timestamp).max

    root_leaf = root_leaf.parent
  end
end

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
root = MerkleTreeLeaf.where(session: "CHAR").first.root
puts root.calculated_hash
puts root.to_dot_digraph
puts ""

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
end
root = MerkleTreeLeaf.where(session: "NUMBER").first.root
puts root.calculated_hash
puts root.to_dot_digraph
puts ""

# binding.irb

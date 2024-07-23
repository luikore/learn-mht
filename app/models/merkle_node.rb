# frozen_string_literal: true

class MerkleNode < ApplicationRecord
  scope :of_tree, ->(tree_hash) { where tree_hash: }

  belongs_to :event, optional: true

  validates :tree_hash, :begin_timestamp, :end_timestamp, :level,
            presence: true,
            allow_blank: false

  class_attribute :hasher, default: Digest::Keccak256
  attr_accessor :parent, :children

  def readonly?
    persisted? && event
  end

  def tree_root
    MerkleNode.of_tree(tree_hash).order(level: :desc).first!
  end

  def calculate_hash
    self.calculated_hash ||=
      if event
        event.eid
      else
        load_children if children.nil?

        MerkleNode.calculate_hash(children.map(&:calculate_hash).join)
      end
  end

  def calculate_hash!
    self.calculated_hash = nil
    calculated_hash
  end

  # A consistency proof: if current hash is consistent with a node
  #
  # Returns [{hash: String, reduce: Integer, is_path: Boolean}]
  #
  # The hash of last element in the array is the root hash of the tree.
  #
  # To verify (js):
  #
  # const stack = []
  # for (const elem of proof) {
  #   const hash = elem.hash
  #   const reduce = elem.reduce
  #   // if the node is in the calculation path of inclusion proof
  #   const is_path = elem.is_path
  #   assert(stack.length >= reduce)
  #   if (reduce > 0) {
  #     const children = stack.splice(-reduce)
  #     assert(keccak256("\x01" + children.join("")) === hash)
  #   }
  #   stack.push(hash)
  # }
  # assert(stack.length === 1)
  # assert(stack[0] === rootHash)
  #
  def consistency_proof
    return [] unless event

    # the tree is growing at the same time,
    # this will be our snapshot for traversing
    root_ts =
      MerkleNode
        .of_tree(tree_hash)
        .order(end_timestamp: :desc)
        .limit(1)
        .pluck(:end_timestamp)
        .first
    return [] if not root_ts

    # node's timestamp represents a root in past moment.
    # before that moment, we compute the inclusion.
    # after that moment, we compute the consistency.

    # it is like a binary search-down
    # - when node doesn't overlap with ts, we take the hash
    # - when node overlaps with ts, we drill down to children

    stack = []
    traverse = ->(node) do
      if node.level > 0
        node.load_children_end_with root_ts
        unless (1..2).cover? node.children.size
          raise "bad children size: #{node.children.size} for #{node.id}"
        end
        node.children.each do |child|
          if child.end_timestamp < end_timestamp or child.begin_timestamp > end_timestamp
            stack << node
          else
            traverse[child]
          end
        end
      end
      stack << node
    end
    traverse[self]

    stack.map! do |n|
      is_path = (n.end_timestamp == end_timestamp)
      hash = (n.calculated_hash ||= MerkleNode.calculate_hash(n.children.map(&:calculated_hash).join))
      { reduce: n.children&.size || 0, hash:, is_path: }
    end
    stack
  end

  # An (inclusion) proof: the nodes required to compute the hash of timestamp.
  #
  # Returns [{hash: String, reduce: Integer, is_path: Boolean}]
  #
  # The hash of last element in the array is the root hash of the tree.
  #
  # To verify (js):
  #
  # const stack = []
  # for (const elem of proof) {
  #   const hash = elem.hash
  #   const reduce = elem.reduce
  #   const is_path = elem.is_path # if the node is in the calculation path
  #   assert(stack.length >= reduce)
  #   if (reduce > 0) {
  #     const children = stack.splice(-reduce)
  #     assert(keccak256("\x01" + children.join("")) === hash)
  #   }
  #   stack.push(hash)
  # }
  # assert(stack.length === 1)
  # assert(stack[0] === rootHash)
  #
  def inclusion_proof
    return [] unless event

    tree_hash = event.merkle_tree_hash
    timestamp = event.created_at.to_i
    leaf = MerkleNode.of_tree(tree_hash).find_by!(end_timestamp: timestamp, level: 0)
    if leaf.nil?
      return []
    end
    # TODO: min_timestamp for each tree can be cached in memory, or, we just keep it 0
    min_timestamp =
      MerkleNode
        .of_tree(tree_hash)
        .order(begin_timestamp: :asc)
        .limit(1)
        .pluck(:begin_timestamp)
        .first

    # begin_timestamp = min_timestamp, means the node was once a root
    root_at_timestamp =
      MerkleNode
        .of_tree(tree_hash)
        .order(level: :asc)
        .find_by!("begin_timestamp = ? and end_timestamp >= ?", min_timestamp, timestamp)

    # search down, until the leaf
    if root_at_timestamp.level > 0
      root_at_timestamp.calculated_hash = nil
    end
    node = root_at_timestamp
    while node.level > leaf.level
      node.load_children_end_with timestamp
      unless (1..2).cover? node.children.size
        raise "bad children size: #{node.children.size} for #{node.id}"
      end
      node = node.children.last
      if node.level > leaf.level
        node.calculated_hash = nil
      else
        raise "leaf not matched" if node.id != leaf.id
      end
    end

    # path nodes are referencing each other.
    # traverse bottom-up to get a data structure that can be serialized to json
    path = []
    traverse = -> n {
      if n.children
        n.children.each {|ch| traverse[ch] }
      end
      path << n
    }
    traverse[root_at_timestamp]
    path.map! do |n|
      is_path = (n.level == 0 or n.calculated_hash.nil?)
      hash = (n.calculated_hash ||= MerkleNode.calculate_hash(n.children.map(&:calculated_hash).join))
      { reduce: n.children&.size || 0, hash:, is_path: }
    end
    path
  end

  def self.push_leaves!(events)
    return if events.empty?

    # TODO: check events' topic, session, and sorted

    # assume all events in the same tree, and ordered by timestamp
    tree_hash = events.first.merkle_tree_hash

    # create leaf (nodes created from bottom-up)
    to_create_nodes = events.map do |event|
      {
        tree_hash:,
        event_id: event.id,
        calculated_hash: event.eid,
        begin_timestamp: event.created_at.to_i, end_timestamp: event.created_at.to_i,
        level: 0, full: true
      }
    end

    max_timestamp =
      of_tree(tree_hash)
        .where("end_timestamp < ?", events.first.created_at.to_i)
        .order(end_timestamp: :desc)
        .limit(1)
        .pluck(:end_timestamp)
        .first

    root_level = 0
    if max_timestamp
      # query newest nodes in previous tree, including all levels
      frontiers =
        of_tree(tree_hash)
          .where("level > ? and end_timestamp = ?", 0, max_timestamp)
          .order(level: :asc)
          .pluck(:id, :full, :level)
      frontiers.each do |row|
        row << nil # [id, full, level, to_create_node]
        root_level = row[2]
      end
    else
      frontiers = []
    end
    tainted_nodes = {} # id => [full, end_timestamp]

    min_timestamp = nil
    events.each do |event|
      # perform carried arithmetic in radix-2: create parallel branch aligned to full branches bottom-up
      # until we fill a middle-layer branch to full
      low_level = true
      frontiers.map! do |(id, full, level, to_create_node)|
        if low_level
          if full # parallel branch
            id = nil
            full = false
            to_create_node = {
              tree_hash:, begin_timestamp: event.created_at.to_i, end_timestamp: event.created_at.to_i, level:, full:
            }
            to_create_nodes << to_create_node
          else
            full = true
            low_level = false
            if id
              tainted_nodes[id] = [full, event.created_at.to_i]
            else
              to_create_node[:full] = full
              to_create_node[:end_timestamp] = event.created_at.to_i
            end
          end
        else
          if id
            tainted_nodes[id] = [full, event.created_at.to_i]
          else
            to_create_node[:end_timestamp] = event.created_at.to_i
          end
        end
        [id, full, level, to_create_node]
      end

      # all layers in frontiers are full, increase tree height
      if low_level
        if min_timestamp.nil? and max_timestamp
          min_timestamp =
            of_tree(tree_hash)
              .order(begin_timestamp: :asc)
              .limit(1)
              .pluck(:begin_timestamp)
              .first
        end
        if min_timestamp
          # a root is always full
          root_level += 1
          to_create_node = {
            tree_hash:, begin_timestamp: min_timestamp, end_timestamp: event.created_at.to_i, level: root_level, full: true
          }
          to_create_nodes << to_create_node
          frontiers << [nil, true, root_level, to_create_node]
        else
          # event is the first leaf, no need to add root
        end
        min_timestamp ||= event.created_at.to_i
      end
    end

    reverse_indexed_tainted_nodes = {}
    tainted_nodes.each do |id, k|
      (reverse_indexed_tainted_nodes[k] ||= []) << id
    end
    reverse_indexed_tainted_nodes.each do |(full, end_timestamp), ids|
      # TODO: set updated_at to now()
      where(id: ids).update_all calculated_hash: nil, full:, end_timestamp:
    end
    create! to_create_nodes
  end

  def self.push_leaves_with_lock!(events)
    lock_key = "push_leaves_#{events.first.merkle_tree_hash}"
    with_advisory_lock(lock_key) do
      push_leaves! events
    end
  end

  def self.tree_root(tree_hash)
    where(tree_hash:).order(level: :desc).first!
  end

  # rehash tainted nodes in a tree
  def self.untaint!(tree_hash)
    hash_cache_by_id = {}

    # single sql to find all nodes for update
    # upcase first SELECT for proper benchmark
    # TODO: in batch of 1000
    connection.execute(sanitize_sql_array(["SELECT id,
    (select json_build_object('ids', json_agg(n.id), 'hashes', json_agg(n.calculated_hash)) from merkle_nodes n where
    n.tree_hash = ? and n.level = m.level - 1 and (n.begin_timestamp = m.begin_timestamp or n.end_timestamp = m.end_timestamp)) as children
    from merkle_nodes m where m.tree_hash = ? and m.calculated_hash is null order by m.level asc", tree_hash, tree_hash])).each do |row|
      parent_id = row["id"]
      children = JSON.parse row["children"]
      raise "bad children size: #{children["ids"].size} for #{row["id"]}" if children["ids"].size > 2
      children_hashes = children["ids"].zip(children["hashes"]).to_a.sort_by(&:first).map do |(child_id, child_hash)|
        child_hash || hash_cache_by_id[child_id]
      end.join
      h = calculate_hash(children_hashes)
      where(id: parent_id).update_all calculated_hash: h
      hash_cache_by_id[parent_id] = h
    end
  end

  def self.calculate_hash(s)
    MerkleNode.hasher.digest("\x01#{s}")
  end

  def load_parent
    self.parent = MerkleNode
                    .of_tree(tree_hash)
                    .find_by("level = ? and (begin_timestamp = ? or end_timestamp = ?)", level + 1, begin_timestamp, end_timestamp)
  end

  def load_children
    self.children = MerkleNode
                      .of_tree(tree_hash)
                      .where(
                        "level = ? and (begin_timestamp = ? or end_timestamp = ?)",
                        level - 1, begin_timestamp, end_timestamp
                      )
                      .order(begin_timestamp: :asc)
                      .to_a
  end

  def load_children_end_with(child_end_timestamp)
    self.children = MerkleNode
                      .of_tree(tree_hash)
                      .where(
                        "level = ? and (begin_timestamp = ? or end_timestamp = ?) and begin_timestamp <= ?",
                        level - 1, begin_timestamp, end_timestamp, child_end_timestamp
                      )
                      .order(begin_timestamp: :asc)
                      .to_a
  end

  def load_ancestors
    # TODO: with recursive CTE
    node = self
    while node
      node.load_parent
      node = node.parent
    end
  end

  def load_descendants
    if level == 0
      return []
    end
    nodes = MerkleNode
              .of_tree(tree_hash)
              .where(
                "begin_timestamp >= ? and end_timestamp <= ? and level < ?",
                begin_timestamp, end_timestamp, level
              )
              .order(level: :asc, begin_timestamp: :asc)
              .to_a
    nodes_by_level = nodes.group_by(&:level).sort_by(&:first).map(&:last)
    nodes_by_level.each_cons(2) do |leafs, branches|
      branches_by_begin_timestamp = branches.group_by(&:begin_timestamp)
      branches_by_end_timestamp = branches.group_by(&:end_timestamp)
      leafs.each do |child|
        parent = branches_by_begin_timestamp[child.begin_timestamp]&.first
        parent ||= branches_by_end_timestamp[child.end_timestamp]&.first
        (parent.children ||= []) << child
      end
    end
    self.children = nodes_by_level.last
    nodes # nodes in bottom-up order
  end

  def to_dot_digraph_label
    "#{id}:#{calculated_hash}"
  end

  def to_dot_digraph
    nodes = load_descendants
    nodes << self
    out = ["digraph G {\n"]
    nodes.each do |d|
      if d.level > 0
        d.children.each do |c|
          out << "  \"#{d.id}\" -> \"#{c.id}\"\n"
        end
      end
      out << "  \"#{d.id}\" [label=\"#{d.to_dot_digraph_label}\"]\n"
    end
    out << "}\n"
    out.join
  end

  # truncate old nodes
  def self.truncate(_before_id)
    raise NotImplementedError
  end
end

# frozen_string_literal: true

class MerkleNode < ApplicationRecord
  scope :of, ->(session) { where session: }

  belongs_to :event, optional: true

  attr_accessor :parent, :children

  def self.push_leaves!(events)
    return if events.empty?

    # assume all events in the same session, and ordered by timestamp
    session = events.first.session

    # create leaf (nodes created from bottom-up)
    to_create_nodes = events.map do |event|
      {
        event_id: event.id, session:, begin_ts: event.timestamp, end_ts: event.timestamp,
        level: 0, full: true, calculated_hash: event.hashed_data
      }
    end

    max_timestamp, = where("session = ? and end_ts < ?", events.first.session, events.first.timestamp).order(end_ts: :desc).limit(1).pluck :end_ts

    root_level = 0
    if max_timestamp
      # query newest nodes in previosu tree, including all levels
      frontier = where("session = ? and level > ? and end_ts = ?", session, 0, max_timestamp).order(level: :asc).pluck(:id, :full, :level)
      frontier.each do |row|
        row << nil # [id, full, level, to_create_node]
        root_level = row[2]
      end
    else
      frontier = []
    end
    tainted_nodes = {} # id => [full, end_ts]

    min_timestamp = nil
    events.each do |event|
      # perform carried arithmetic in radix-2: create parallel branch aligned to full branches bottom-up
      # until we fill a middle-layer branch to full
      low_level = true
      frontier.map! do |(id, full, level, to_create_node)|
        if low_level
          if full # parallel branch
            id = nil
            full = false
            to_create_node = {
              session:, begin_ts: event.timestamp, end_ts: event.timestamp, level:, full:
            }
            to_create_nodes << to_create_node
          else
            full = true
            low_level = false
            if id
              tainted_nodes[id] = [full, event.timestamp]
            else
              to_create_node[:full] = full
              to_create_node[:end_ts] = event.timestamp
            end
          end
        else
          if id
            tainted_nodes[id] = [full, event.timestamp]
          else
            to_create_node[:end_ts] = event.timestamp
          end
        end
        [id, full, level, to_create_node]
      end

      # all layers in frontier are full, increase tree height
      if low_level
        if min_timestamp.nil? and max_timestamp
          min_timestamp, = where(session:).order(begin_ts: :asc).limit(1).pluck :begin_ts
        end
        if min_timestamp
          # a root is always full
          root_level += 1
          to_create_node = {
            session:, begin_ts: min_timestamp, end_ts: event.timestamp, level: root_level, full: true
          }
          to_create_nodes << to_create_node
          frontier << [nil, true, root_level, to_create_node]
        else
          # event is the first leaf, no need to add root
        end
        min_timestamp ||= event.timestamp
      end
    end

    reverse_indexed_tainted_nodes = {}
    tainted_nodes.each do |id, k|
      (reverse_indexed_tainted_nodes[k] ||= []) << id
    end
    reverse_indexed_tainted_nodes.each do |(full, end_ts), ids|
      # TODO: set updated_at to now()
      where(id: ids).update_all calculated_hash: nil, full:, end_ts:
    end
    create to_create_nodes
  end

  def self.root(session)
    where(session: session).order(level: :desc).first
  end

  # rehash tainted nodes in a session
  def self.untaint!(session, hasher)
    hash_cache_by_id = {}

    # single sql to find all nodes for update
    # upcase first SELECT for proper benchmark
    # TODO: in batch of 1000
    connection.execute(sanitize_sql_array(["SELECT id,
    (select json_build_object('ids', json_agg(n.id), 'hashes', json_agg(n.calculated_hash)) from merkle_nodes n where
    n.session = ? and n.level = m.level - 1 and (n.begin_ts = m.begin_ts or n.end_ts = m.end_ts)) as children
    from merkle_nodes m where m.session = ? and m.calculated_hash is null order by m.level asc", session, session])).each do |row|
      parent_id = row["id"]
      children = JSON.parse row["children"]
      raise "bad children size: #{children["ids"].size} for #{row["id"]}" if children["ids"].size > 2
      children_hashes = children["ids"].zip(children["hashes"]).to_a.sort_by(&:first).map do |(child_id, child_hash)|
        child_hash ||= hash_cache_by_id[child_id]
      end.join
      h = hasher.digest("\x01#{children_hashes}")
      where(id: parent_id).update_all calculated_hash: h
      hash_cache_by_id[parent_id] = h
    end
  end

  def load_parent
    self.parent = MerkleNode.where("session = ? and level = ? and (begin_ts = ? or end_ts = ?)", session, level + 1, begin_ts, end_ts).first
  end

  def load_children
    self.children = MerkleNode.where(
      "session = ? and level = ? and (begin_ts = ? or end_ts = ?)", session, level - 1, begin_ts, end_ts
    ).order(begin_ts: :asc).to_a
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
    nodes = MerkleNode.where(
      "session = ? and begin_ts >= ? and end_ts <= ? and level < ?", session, begin_ts, end_ts, level
    ).order(
      level: :asc, begin_ts: :asc
    ).to_a
    nodes_by_level = nodes.group_by(&:level).to_a.sort_by(&:first).map(&:last)
    nodes_by_level.each_cons 2 do |leafs, branches|
      branches_by_begin_ts = branches.group_by &:begin_ts
      branches_by_end_ts = branches.group_by &:end_ts
      leafs.each do |child|
        parent = branches_by_begin_ts[child.begin_ts]&.first
        parent ||= branches_by_end_ts[child.end_ts]&.first
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
  def self.truncate(before_id)
    TODO
  end
end

# frozen_string_literal: true

class MerkleNode < ApplicationRecord
  scope :of, ->(session) { where session: }

  belongs_to :event, optional: true

  attr_accessor :parent, :children

  # 插入新叶子，应该用事务包裹，不计算哈希，所以事务时长不受哈希计算影响
  def self.push_leaf!(event)
    timestamp = event.timestamp
    session = event.session

    # 创建叶子 (创建顺序从低到高)
    to_create_nodes = [{
      event: event, session: session, begin_ts: timestamp, end_ts: timestamp,
      level: 0, full: true, calculated_hash: event.hashed_data
    }]

    max_timestamp, = where("session = ? and end_ts < ?", session, timestamp).order(end_ts: :desc).limit(1).pluck :end_ts

    if max_timestamp
      # 查询前树最新的节点，每 level 一个
      frontier = where("session = ? and level > ? and end_ts = ?", session, 0, max_timestamp).order(level: :asc).select(:id, :full, :level).to_a

      root_level = (frontier.empty? ? 0 : frontier.last.level)
      # 进位: 低层有多少 full 就创建多少个同层的新节点，直到将一个中层节点变成 full
      low_level = true
      update_node_ids = []
      taint_node_ids = []
      frontier.each do |node|
        if low_level
          if node.full
            to_create_nodes << {
              session: session, begin_ts: timestamp, end_ts: timestamp, level: node.level, full: false
            }
          else
            update_node_ids << node.id
            low_level = false
          end
        else
          taint_node_ids << node.id
        end
        node
      end

      if update_node_ids.size + taint_node_ids.size + to_create_nodes.size != root_level + 1
        raise "inconsistency in nodes -- update_nodes(#{update_node_ids.size}) + taint_nodes(#{taint_node_ids.size}) + create_nodes(#{to_create_nodes.size}) != levels(#{root_level + 1})"
      end

      # frontier 各层全满，增加树高
      if low_level
        min_timestamp, = where(session: session).order(begin_ts: :asc).limit(1).pluck :begin_ts
        # 根总是满的
        to_create_nodes << {
          session: session, begin_ts: min_timestamp, end_ts: timestamp, level: root_level + 1, full: true
        }
      end

      if update_node_ids.present?
        where(id: update_node_ids).update_all full: true, calculated_hash: nil, end_ts: timestamp
      end
      if taint_node_ids.present?
        where(id: taint_node_ids).update_all calculated_hash: nil, end_ts: timestamp
      end
    end

    create to_create_nodes
  end

  def self.root(session)
    where(session: session).order(level: :desc).first
  end

  # 更新哈希
  def self.untaint!(session, hasher)
    hash_cache_by_id = {}

    # single sql to update all nodes
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

  # 更新 parent 属性
  def load_parent!
    self.parent = MerkleNode.where("session = ? and level = ? and (begin_ts = ? or end_ts = ?)", session, level + 1, begin_ts, end_ts).first
  end

  # 更新 children 属性
  def load_children!
    self.children = MerkleNode.where(
      "session = ? and level = ? and (begin_ts = ? or end_ts = ?)", session, level - 1, begin_ts, end_ts
    ).order(begin_ts: :asc).to_a
  end

  # 一个节点的所有先代，按 level 组织起来，并更新 parent 属性
  def load_ancestors!
    node = self
    while node
      node.load_parent!
      node = node.parent
    end
  end

  # 一个节点的所有后代，按 level 组织起来，并更新 children 属性
  # 返回从低到高排序的节点列表
  def load_descendants!
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
    nodes
  end

  def to_dot_digraph_label
    "#{id}:#{calculated_hash}"
  end

  def to_dot_digraph
    nodes = load_descendants!
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

  # 清理旧节点
  def self.truncate(before_id)
    TODO
  end
end

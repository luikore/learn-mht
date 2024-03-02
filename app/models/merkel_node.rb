# frozen_string_literal: true

class MerkelNode < ApplicationRecord
  scope :of, ->(session) { where session: }

  belongs_to :event, optional: true

  attr_accessor :parent, :children

  # 插入新叶子，应该用事务包裹，不计算哈希，所以事务时长不受哈希计算影响
  def self.push_leaf!(event)
    timestamp = event.timestamp
    session = event.session

    max_timestamp, = where("session = ? and end_ts < ?", session, timestamp).order(end_ts: :desc).limit(1).pluck :end_ts

    if max_timestamp
      # 查询前树最新的节点，每 level 一个
      frontier = where("session = ? and level > ? and end_ts = ?", session, 0, max_timestamp).order(level: :asc).to_a

      # 进位: 低层有多少 full 就创建多少个同层的新节点，直到将一个中层节点变成 full
      low_level = true
      frontier.each do |node|
        if low_level
          if node.full
            node = create!(session: session, begin_ts: timestamp, end_ts: timestamp, level: node.level, full: false)
          else
            node.calculated_hash = nil
            node.full = true
            node.end_ts = timestamp
            node.save!
            low_level = false
          end
        else
          node.calculated_hash = nil
          node.end_ts = timestamp
          node.save!
        end
      end

      # frontier 各层全满，增加树高
      if low_level
        min_timestamp, = where(session: session).order(begin_ts: :asc).limit(1).pluck :begin_ts
        largest_level = (frontier.empty? ? 0 : frontier.last.level)
        # 根总是满的
        create!(session: session, begin_ts: min_timestamp, end_ts: timestamp, level: largest_level + 1, full: true)
      end
    end

    # 创建叶子
    create!(event: event, session: session, begin_ts: timestamp, end_ts: timestamp,
      level: 0, full: true, calculated_hash: event.hashed_data)
  end

  def self.root(session)
    where(session: session).order(level: :desc).first
  end

  # 更新哈希
  def self.untaint!(session, hasher)
    where(session: session, calculated_hash: nil).order(level: :asc).each do |node|
      node.load_children!
      h = hasher.digest("\x01" + node.children.map(&:calculated_hash).join)
      where(id: node.id).update calculated_hash: h
    end
  end

  # 更新 parent 属性
  def load_parent!
    self.parent = MerkelNode.where("session = ? and level = ? and (begin_ts = ? or end_ts = ?)", session, level + 1, begin_ts, end_ts).first
  end

  # 更新 children 属性
  def load_children!
    self.children = MerkelNode.where(
      "session = ? and level = ? and begin_ts >= ? and end_ts <= ?", session, level - 1, begin_ts, end_ts
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
    nodes = MerkelNode.where(
      "session = ? and begin_ts >= ? and end_ts <= ? and level < ?", session, begin_ts, end_ts, level
    ).order(
      level: :asc, begin_ts: :asc
    ).to_a
    nodes_by_level = nodes.group_by(&:level).to_a.sort_by(&:first).map(&:last)
    nodes_by_level.each_cons 2 do |leafs, branches|
      branches_by_begin_ts = branches.group_by &:begin_ts
      branches_by_end_ts = branches.group_by &:end_ts
      leafs.each do |child|
        parent = branches_by_begin_ts[child.begin_ts]&.find { |n| n.level == child.level + 1 }
        parent ||= branches_by_end_ts[child.end_ts]&.find { |n| n.level == child.level + 1 }
        (parent.children ||= []) << child
      end
    end
    self.children = nodes.select { |n| n.level == level - 1 }
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

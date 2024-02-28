# frozen_string_literal: true

class CreateMerkleTreeLeaves < ActiveRecord::Migration[7.2]
  def change
    create_table :merkle_tree_leaves do |t|
      t.integer :parent_id # 父节点，closure_tree gem 需要

      t.string :calculated_hash, null: false # 计算好的哈希

      t.string :session, null: false # 一棵树的唯一标识
      t.integer :timestamp, null: false # 对应 Event 的时间戳，用于排序，时间早的为树的左节点，晚的为右节点
      t.references :event # 如果是叶子节点，那么将关联一个对应的 Event
    end
  end
end

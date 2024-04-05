# frozen_string_literal: true

class CreateMerkleNodes < ActiveRecord::Migration[7.2]
  def change
    # 创建顺序：parent to children
    create_table :merkle_nodes do |t|
      t.string :tree_hash, null: false # 一棵树的唯一标识
      t.references :event, foreign_key: true # 如果是叶子节点，那么将关联一个对应的 Event

      t.string :calculated_hash # 计算好的哈希, 可以延迟计算，避免相互依赖
      t.string :calculated_tree_root_hash # 计算好的当时树根的哈希, 可以延迟计算 TODO: 这个真的需要吗？

      # 对应 Event 的 timestamp，用于排序，时间早的为树的左节点，晚的为右节点, parent 包含最新子节点的 timestamp
      # 每棵子树都是连续的一系列节点，只需要记录开始和结束节点 timestamp
      # 通过 timestamp range 可以:
      # - 查询所有后代
      # - 查询直接父
      # - 查询所有祖先
      t.integer :begin_timestamp, null: false # begin_timestamp = 0 的为创世节点 (同 level 没有更老的了)
      t.integer :end_timestamp, null: false

      t.boolean :full, null: false, default: false # 节点是否已满, 创建时未满，添加子节点时设为满
      t.integer :level, null: false # 叶子 level=0。任意 parent.level = child.level + 1

      t.index :tree_hash
      t.index :begin_timestamp
      t.index :end_timestamp
      t.index :calculated_hash, where: "calculated_hash is null"
    end
  end
end

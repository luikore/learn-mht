# frozen_string_literal: true

class CreateMerkleTreeLeaves < ActiveRecord::Migration[7.2]
  def change
    create_table :merkle_tree_leaves do |t|
      t.integer :parent_id

      t.string :calculated_hash, null: false
      t.integer :sort_order, null: false, default: 0

      t.string :session, null: false
      t.references :event
    end
  end
end

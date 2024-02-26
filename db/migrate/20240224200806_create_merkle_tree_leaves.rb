# frozen_string_literal: true

class CreateMerkleTreeLeaves < ActiveRecord::Migration[7.2]
  def change
    create_table :merkle_tree_leaves do |t|
      t.integer :parent_id

      t.string :signer, null: false
      t.integer :timestamp, null: false
      t.string :data
      t.string :hashed_data, null: false
      t.string :signed_hashed_data, null: false
    end
  end
end

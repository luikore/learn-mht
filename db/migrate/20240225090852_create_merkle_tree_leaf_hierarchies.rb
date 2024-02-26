# frozen_string_literal: true

class CreateMerkleTreeLeafHierarchies < ActiveRecord::Migration[7.2]
  def change
    create_table :merkle_tree_leaf_hierarchies, id: false do |t|
      t.integer :ancestor_id, null: false
      t.integer :descendant_id, null: false
      t.integer :generations, null: false

      t.index %i[ancestor_id descendant_id generations], unique: true, name: "merkle_tree_leaf_anc_desc_idx"
      t.index :descendant_id, name: "merkle_tree_leaf_desc_idx"
    end
  end
end

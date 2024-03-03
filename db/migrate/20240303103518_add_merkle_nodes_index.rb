# frozen_string_literal: true

class AddMerkleNodesIndex < ActiveRecord::Migration[7.2]
  def up
    add_index :merkle_nodes, :session
    add_index :merkle_nodes, :begin_ts
    add_index :merkle_nodes, :end_ts
    add_index :merkle_nodes, :calculated_hash, where: "calculated_hash is null"
  end

  def down
    remove_index :merkle_nodes, :session
    remove_index :merkle_nodes, :begin_ts
    remove_index :merkle_nodes, :end_ts
    remove_index :merkle_nodes, :calculated_hash, where: "calculated_hash is null"
  end
end

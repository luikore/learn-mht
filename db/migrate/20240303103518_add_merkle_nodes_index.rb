# frozen_string_literal: true

class AddMerkleNodesIndex < ActiveRecord::Migration[7.2]
  def change
    change_table :merkle_nodes do |t|
      t.index :session
      t.index :begin_ts
      t.index :end_ts
      t.index :calculated_hash, where: "calculated_hash is null"
    end
  end
end

# frozen_string_literal: true

class MerkleTreeLeaf < ApplicationRecord
  has_closure_tree order: "timestamp"

  def to_digraph_label
    hashed_data
  end
end

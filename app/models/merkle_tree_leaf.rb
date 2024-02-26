# frozen_string_literal: true

class MerkleTreeLeaf < ApplicationRecord
  has_closure_tree order: "sort_order", numeric_order: true

  belongs_to :event, optional: true

  def to_digraph_label
    calculated_hash
  end
end

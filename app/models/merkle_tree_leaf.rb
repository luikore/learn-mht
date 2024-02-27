# frozen_string_literal: true

class MerkleTreeLeaf < ApplicationRecord
  has_closure_tree order: "timestamp"

  belongs_to :event, optional: true

  def to_digraph_label
    # "#{id}:#{calculated_hash}"
    calculated_hash
  end
end

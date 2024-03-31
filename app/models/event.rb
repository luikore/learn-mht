# frozen_string_literal: true

class Event < ApplicationRecord
  has_one :merkle_node, dependent: :restrict_with_exception

  scope :of_signer_and_session, ->(signer, session) { where(signer: signer, session: session) }

  after_create :add_to_merkle_tree

  validates :raw, :raw_hash, :signature, :timestamp, :session, :nonce, :signer,
            presence: true

  validates :nonce,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }, uniqueness: {
              scope: %i[signer session]
            }

  # This is strict, but we don't do this for now
  # validates :nonce,
  #           comparison: {
  #             equal_to: ->(current) {
  #               of_signer_and_session(current.signer, current.session)
  #                 .order(nonce: :desc)
  #                 .limit(1)
  #                 .pluck(:nonce)
  #                 .first || 0
  #             }
  #           }

  validates :nonce,
            comparison: {
              greater_than: ->(current) {
                of_signer_and_session(current.signer, current.session)
                  .order(nonce: :desc)
                  .limit(1)
                  .pluck(:nonce)
                  .first || -1
              }
            }

  def readonly?
    persisted?
  end

  def merkle_tree_hash
    Digest::Keccak256.digest([signer, session].join)
  end

  def merkle_tree_root
    merkle_node.tree_root
  end

  def inclusion_proof
    merkle_node.inclusion_proof
  end

  private

  def add_to_merkle_tree
    return if new_record?
    return if MerkleNode.where(event: self).exists?

    lock_key = "add_to_merkle_tree_#{merkle_tree_hash}"
    with_advisory_lock(lock_key) do
      MerkleNode.push_leaves!([self])
      MerkleNode.untaint!(merkle_tree_hash)
    end
  end
end

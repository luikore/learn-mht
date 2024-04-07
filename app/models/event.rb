# frozen_string_literal: true

class Event < ApplicationRecord
  include Nostr::Nip1

  scope :of_pubkey, ->(pubkey) { where(pubkey:) }
  scope :of_topic, ->(topic) { where(topic:) }
  scope :of_session, ->(session) { where(session:) }

  has_one :merkle_node, dependent: :restrict_with_exception

  after_create :add_to_merkle_tree

  # A publisher must not send events in the same time which makes harder to sort them.
  validates :created_at,
            uniqueness: {
              scope: :pubkey
            },
            comparison: {
              greater_than: ->(current) {
                current.latest&.created_at || 0
              }
            }

  validates :topic,
            presence: true,
            length: { is: 64 },
            format: { with: /\A\h+\z/ }

  validates :session,
            presence: true,
            length: { maximum: 4 }

  before_validation do
    self.session = tags.find { |tag| tag[0] == "s" }&.[](1)
    self.topic = tags.find { |tag| tag[0] == "t" }&.[](1)

    # TODO: TEST ONLY, remove on next reset
    self.session ||= "test"
    self.topic ||= Digest::Keccak256.digest("test")
  end

  def readonly?
    persisted?
  end

  def merkle_tree_hash
    Digest::Keccak256.digest([pubkey, topic, session].join)
  end

  def merkle_tree_root
    merkle_node&.tree_root
  end

  def inclusion_proof
    merkle_node&.inclusion_proof
  end

  def latest
    @latest ||=
      Event
        .of_topic(topic)
        .of_pubkey(pubkey)
        .of_session(session)
        .order(id: :desc)
        .first
  end

  def reload(options = nil)
    @latest = nil
    super
  end

  class << self
    def from_raw(nip1_json)
      return new unless nip1_json

      new(
        eid: nip1_json.fetch("id"),
        pubkey: nip1_json.fetch("pubkey"),
        created_at: nip1_json.fetch("created_at"),
        kind: nip1_json.fetch("kind"),
        tags: nip1_json.fetch("tags"),
        content: nip1_json.fetch("content"),
        sig: nip1_json.fetch("sig")
      )
    end
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

# frozen_string_literal: true

module Nostr
  module Nip1
    extend ActiveSupport::Concern

    # AVAILABLE_FILTERS = SubscriptionQueryBuilder::AVAILABLE_FILTERS.map { |filter_name| /\A[a-zA-Z]\Z/.match?(filter_name) ? "##{filter_name}" : filter_name }

    KNOWN_KIND_TYPES = {
      text_note: 1,
      dephy_message: 1111
    }

    included do
      normalizes :eid, with: ->(eid) { eid.strip.downcase }
      normalizes :pubkey, with: ->(pubkey) { pubkey.strip.downcase }
      normalizes :sig, with: ->(sig) { sig.strip.downcase }

      validates :eid,
                presence: true,
                uniqueness: true,
                length: { is: 64 },
                format: { with: /\A\h+\z/ }
      validates :pubkey,
                presence: true,
                length: { is: 64 },
                format: { with: /\A\h+\z/ }
      validates :kind,
                presence: true,
                inclusion: {
                  in: KNOWN_KIND_TYPES.values
                }
      validates :content,
                presence: true
      validates :sig,
                presence: true,
                length: { is: 128 },
                format: { with: /\A\h+\z/ }
      validate :id_must_match_payload
      validate :sig_must_match_payload

      def created_at=(value)
        value.is_a?(Numeric) ? super(Time.at(value)) : super(value)
      end

      def serialized_nostr_event
        [
          0,
          pubkey,
          created_at.to_i,
          kind,
          tags,
          content.to_s
        ]
      end

      def serialized_nostr_event_json
        serialized_nostr_event.to_json
      end

      def nip1_hash
        {
          id: eid,
          pubkey:,
          created_at: created_at.to_i,
          kind:,
          tags: tags,
          content:,
          sig:
        }
      end
      def nip1_json
        nip1_hash.to_json
      end

      def computed_eid
        Digest::SHA256.hexdigest(serialized_nostr_event_json)
      end

      def schnorr_signature_verified?
        schnorr_params = {
          message: [eid].pack("H*"),
          pubkey: [pubkey].pack("H*"),
          sig: [sig].pack("H*")
        }
        Secp256k1::SchnorrSignature.from_data(schnorr_params[:sig])
                                   .verify(
                                     schnorr_params[:message],
                                     Secp256k1::XOnlyPublicKey.from_data(schnorr_params[:pubkey])
                                   )
      rescue Secp256k1::DeserializationError => _ex
        false
      end

      private

      def id_must_match_payload
        unless computed_eid == eid
          errors.add(:eid, "must match payload")
        end
      end

      def sig_must_match_payload
        unless schnorr_signature_verified?
          errors.add(:sig, "must match payload")
        end
      end
    end
  end
end

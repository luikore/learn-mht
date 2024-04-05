# frozen_string_literal: true

module Api
  class EventsController < ::Api::Topics::ApplicationController
    def index
      @_pagy, @records = pagy_cursor(
        Event.of_topic(@topic),
        after: params[:after], primary_key: :id, order: { id: :asc }
      )
    end

    def show
    end

    private

    def event_json(event)
      {
        raw: event.raw,
        raw_hash: event.raw_hash,
        signature: event.signature,
        timestamp: event.timestamp,
        session: event.session,
        nonce: event.nonce,
        signer: event.signer,
        topic: event.topic
      }
    end
  end
end

# frozen_string_literal: true

module Api::Topics
  class EventsController < ::Api::Topics::ApplicationController
    def index
      @pagy, @records = pagy_uuid_cursor(
        Event.of_topic(@topic),
        after: params[:after], primary_key: :eid, order: { id: :asc }
      )

      render json: {
        status: "ok",
        events: @records.map(&:nip1_hash),
        pagination: {
          has_more: @pagy.has_more?
        }
      }
    end
  end
end

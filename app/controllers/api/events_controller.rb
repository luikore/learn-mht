# frozen_string_literal: true

module Api
  class EventsController < ::Api::ApplicationController
    def show
      @event = Event.find_by!(eid: params[:id])

      render json: {
        status: "ok",
        event: @event.nip1_hash,
        extra: {
          topic: @event.topic,
          session: @event.session,
          latest: {
            id: @event.latest.eid,
            created_at: @event.latest.created_at.to_i
          },
          root_hash: @event.merkle_tree_root.calculated_hash,
          inclusion_proof: @event.inclusion_proof
        }
      }
    rescue ActiveRecord::RecordNotFound => _ex
      render json: {
        status: "error",
        error: {
          message: "Event not found"
        }
      }, status: :not_found
    end
  end
end

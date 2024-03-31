# frozen_string_literal: true

module Bridging
  class EventsController < Bridging::ApplicationController
    def create
      @event = Event.new event_params

      if @event.save
        render json: {
          status: "ok",
          event: event_json(@event)
        }
      else
        render json: {
          status: "error",
          error: {
            messages: @event.errors.messages
          }
        }
      end
    end

    def batch_create
      error = nil
      Event.transaction do
        events_params.each_with_index do |permitted_params, i|
          # Don't use batch insert for now because we want to validate the nonce here
          # Could be optimize in the future
          event = Event.new(permitted_params)
          unless event.save
            if event.errors[:nonce].any?
              next
            end

            error = {
              index: i,
              messages: event.errors.messages
            }
            raise ActiveRecord::Rollback
          end
        end
      end

      if error
        render json: {
          status: "error",
          error: error
        }
      else
        render json: {
          status: "ok"
        }
      end
    end

    private

    def event_params
      params.require(:event).permit(
        :raw, :raw_hash, :signature, :timestamp, :session, :nonce, :signer
      )
    end

    def events_params
      params.slice(:events).permit(events: [
        :raw, :raw_hash, :signature, :timestamp, :session, :nonce, :signer
      ]).require(:events)
    end

    def event_json(event)
      {
        raw: event.raw,
        raw_hash: event.raw_hash,
        signature: event.signature,
        timestamp: event.timestamp,
        session: event.session,
        nonce: event.nonce,
        signer: event.signer
      }
    end
  end
end

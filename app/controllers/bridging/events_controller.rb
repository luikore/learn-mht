# frozen_string_literal: true

module Bridging
  class EventsController < Bridging::ApplicationController
    def create
      @event = Event.from_raw(event_params)

      if @event.save
        render json: {
          status: "ok",
          event: @event.raw_json
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
        events_params.each_with_index do |nip1_json, i|
          # Don't use batch insert for now because we want to validate data here
          # Could be optimize in the future
          event = Event.from_raw(nip1_json)
          unless event.save
            # if event.errors[:sig].any?
            #   next
            # end

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
      params.require(:event)
    end

    def events_params
      params.require(:events)
    end
  end
end

# frozen_string_literal: true

module Api
  class HomeController < Api::ApplicationController
    def index
      render json: {
        status: "ok"
      }
    end
  end
end

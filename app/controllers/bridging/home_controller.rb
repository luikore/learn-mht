# frozen_string_literal: true

module Bridging
  class HomeController < Bridging::ApplicationController
    def index
      render json: {
        status: "ok"
      }
    end
  end
end

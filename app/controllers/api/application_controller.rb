# frozen_string_literal: true

module Api
  class ApplicationController < ActionController::API
    include Pagy::Backends::UuidCursor
  end
end

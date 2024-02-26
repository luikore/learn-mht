# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.string :signer, null: false
      t.string :session, null: false
      t.index %i[signer session]

      t.string :data, null: false
      t.string :hashed_data, null: false
      t.string :signed_hashed_data, null: false
      t.integer :timestamp, null: false
    end
  end
end

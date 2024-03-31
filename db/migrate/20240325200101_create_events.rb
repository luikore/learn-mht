# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.string :raw, null: false
      t.string :raw_hash, null: false
      t.string :signature, null: false
      t.integer :timestamp, null: false
      t.string :session, null: false
      t.integer :nonce, null: false
      t.string :signer, null: false

      t.index %i[signer session]
      t.index %i[signer session nonce], unique: true
    end
  end
end

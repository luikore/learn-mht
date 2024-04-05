# frozen_string_literal: true

class AddExtendedFieldsToEvents < ActiveRecord::Migration[7.2]
  def change
    change_table :events, id: :string do |t|
      t.string :topic, null: false, index: true
      t.string :session, null: false
    end
  end
end

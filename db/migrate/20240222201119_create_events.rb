# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.string :signer, null: false # 发布消息的人的公钥
      t.string :session, null: false # 会话 ID
      t.index %i[signer session] # 发布消息的人 + 会话 ID 组成了 Event 链的标识

      t.string :data, null: false # 真实的数据
      t.string :hashed_data, null: false # 数据的哈希
      t.string :signed_hashed_data, null: false # 签名过的数据的哈希
      t.integer :timestamp, null: false # 时间戳
    end
  end
end

class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string :db_uid
      t.string :db_access_token
      t.string :db_cursor
      t.string :gh_uid
      t.string :gh_access_token
      t.string :email

      t.timestamps
    end
  end
end

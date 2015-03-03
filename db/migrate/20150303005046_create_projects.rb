class CreateProjects < ActiveRecord::Migration
  def change
    create_table :projects do |t|
      t.references :user
      t.string :repo_id
      t.string :repo_name
    end
  end
end

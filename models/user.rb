class User < ActiveRecord::Base
  has_many :projects
  def delta
    client = DropboxClient.new( self.db_access_token )
    cursor = self.db_cursor
    delta = client.delta cursor
    self.db_cursor = delta["cursor"]
    self.save
    delta
  end
end
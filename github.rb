require 'sinatra/base'
class Github < Sinatra::Base
  def self.login
    "https://github.com/login/oauth/authorize?redirect_uri=#{ENV['GH_CALLBACK']}&scope=public_repo&client_id=#{ENV['GH_CLIENT_ID']}" 
  end
  def self.callback request
    session_code = request.env['rack.request.query_hash']['code']
    result = RestClient.post('https://github.com/login/oauth/access_token', {
      :client_id => ENV['GH_CLIENT_ID'],
      :client_secret => ENV['GH_CLIENT_SECRET'],
      :code => session_code
    },  :accept => :json)
    res = JSON.parse( result )
    return res
  end
  def self.user_info at
    JSON.parse(RestClient.get('https://api.github.com/user?access_token=' + at ))
  end
  def self.create_repo name, at
    repo = {
     name: name
    }
    return HTTParty.post('https://api.github.com/user/repos?access_token=' + at, {
     body: repo.to_json
    }).body
  end
  def self.delete_file path, p
        @p = p
	path = path.gsub(/^\/#{@p.repo_name}/,'')
	commit = {
	  path: path,
	  message: "Deleted by Hubbox - #{Time.now.to_i.to_s}",
	}
	url = URI.escape("https://api.github.com/repos/#{@p.user.gh_login}/#{@p.repo_name}/contents#{commit[:path]}?access_token=" + @p.user.gh_access_token )
	res = HTTParty.get(url).body
	commit[:sha] = JSON.parse(res)['sha']
	res = HTTParty.delete(url,{
	  body: commit.to_json
	}).body
  end
  def self.update_file path, project
	@p = project
	client = DropboxClient.new( @p.user.db_access_token )
	contents = client.get_file( path ) 
	path = path.gsub(/^\/#{@p.repo_name}/,'')
	url = "https://api.github.com/repos/#{@p.user.gh_login}/#{@p.repo_name}/contents#{path}?access_token=" + @p.user.gh_access_token
	res = JSON.parse(HTTParty.get(url).body)
	commit = {
	  path: path,
	  message: "Synced by Hubbox - #{Time.now.to_i.to_s}",
	  content: Base64.encode64(contents),
	  sha: res['sha']
	}
	return HTTParty.put(url,{
	  body: commit.to_json
	}).body
  end
end

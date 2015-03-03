require 'sinatra'
require "base64"
require 'rest-client'
require 'sinatra/base'
require 'httparty'
require 'sinatra/reloader'
require 'sinatra/activerecord'
require 'dropbox_sdk'
require 'pry'
require './env' if File.exists? 'env.rb'
require './models/user'
require './models/project'


  ActiveRecord::Base.establish_connection(
    :adapter => 'sqlite3',
    :database =>  'db/sqlite3.db'
  )

  enable :sessions
  set :session_secret, DB_SESSION_SECRET

  get '/' do
    session['access_token'] ||= ''
    if session['access_token'] != ''
      @dropbox = get_dropbox_client.account_info['display_name']
      @users = User.all
    end
    if session['gh_access_token']
      @github = session['gh_access_token']
    end
    erb :index
  end

  def get_auth
    redirect_uri = DB_CALLBACK
    flow = DropboxOAuth2Flow.new( DB_APP_KEY, DB_APP_SECRET, redirect_uri, session, :dropbox_auth_csrf_token)
  end

  get '/auth/dropbox' do
    auth_url = get_auth.start
    redirect to auth_url
  end

  get '/auth/github' do
    url = GH_CALLBACK
    client_id = GH_CLIENT_ID
    redirect to "https://github.com/login/oauth/authorize?redirect_uri=#{url}&scope=public_repo&client_id=#{client_id}" 
  end

  get '/logout' do
    session.clear
    redirect to '/'
  end

  def get_dropbox_client
    return DropboxClient.new(session[:access_token]) if session[:access_token]
  end

  get '/auth/dropbox/callback' do
    code = params[:code]
    access_token, user_id, url_state = get_auth.finish(params)
    if session['gh_access_token'] && session['gh_access_token'] != ""
      u = User.find_by( gh_access_token: session['gh_access_token'] )
    else
      u = User.find_or_create_by( db_uid: user_id )
    end
    u.db_access_token = access_token
    u.save
    session['access_token'] = access_token
    redirect to '/'
  end

  get '/auth/github/callback' do
    session_code = request.env['rack.request.query_hash']['code']
    result = RestClient.post('https://github.com/login/oauth/access_token', {
      :client_id => GH_CLIENT_ID,
      :client_secret => GH_CLIENT_SECRET,
      :code => session_code
    },  :accept => :json)
    res = JSON.parse( result )
    session['gh_access_token'] = res['access_token']
    user = JSON.parse(RestClient.get('https://api.github.com/user?access_token=' + session['gh_access_token']))
    if session['access_token'] && session['access_token'] != ""
      @u = User.find_by( db_access_token: session['access_token'])
    else
      @u = User.find_or_create_by( gh_uid: user['id'].to_s )
    end
    @u.gh_access_token = session['gh_access_token']
    @u.gh_uid = user["id"].to_s
    @u.gh_login = user["login"]
    @u.save
    redirect to '/'
  end

  post '/projects' do
   repo = {
     name: params["name"]
   }
   res = HTTParty.post('https://api.github.com/user/repos?access_token=' + session['gh_access_token'],{
     body: repo.to_json
   }).body

   @p = Project.new
   @p.repo_id = JSON.parse(res)["id"].to_s
   @p.repo_name = JSON.parse(res)["name"]
   @u = User.find_by(gh_access_token: session['gh_access_token'])
   client = DropboxClient.new( @u.db_access_token )
   client.file_create_folder( @p.repo_name )
   @p.user_id = @u.id
   @p.save
   redirect to '/projects/' + @p.id.to_s
  end
 
  get '/projects/:id' do
    @p = Project.find( params[:id] )
    erb :project
  end

  post '/sync' do
    @p = Project.find( params[:id] )
    client = DropboxClient.new( @p.user.db_access_token )
    u = @p.user
    delta = u.delta
    delta["entries"].each do |f|
      if f[1] == nil
	path = f[0].gsub(/^\/#{@p.repo_name}/,'')
	commit = {
	  path: path,
	  message: "Deleted by Hubbox - #{Time.now.to_i.to_s}",
	}
	url = URI.escape("https://api.github.com/repos/#{@p.user.gh_login}/#{@p.repo_name}/contents#{commit[:path]}?access_token=" + session['gh_access_token'])
	res = HTTParty.get(url).body
	commit[:sha] = JSON.parse(res)['sha']
	res = HTTParty.delete(url,{
	  body: commit.to_json
	}).body
      elsif !f[1]["is_dir"]
	contents = client.get_file( f[1]["path"] ) 
	path = f[1]['path'].gsub(/^\/#{@p.repo_name}/,'')
	commit = {
	  path: path,
	  message: "Synced by Hubbox - #{Time.now.to_i.to_s}",
	  content: Base64.encode64(contents)
	}
	url = "https://api.github.com/repos/#{@p.user.gh_login}/#{@p.repo_name}/contents#{commit[:path]}?access_token=" + session['gh_access_token']
	begin
	  url = "https://api.github.com/repos/#{@p.user.gh_login}/#{@p.repo_name}/contents#{commit[:path]}?access_token=" + session['gh_access_token']
	  res = HTTParty.get(url).body
	  commit[:sha] = JSON.parse(res)['sha']
	rescue
	 end
	puts "updating #{url}"
	res = HTTParty.put(url,{
	  body: commit.to_json
	}).body
      end
    end
    redirect to '/projects/' + @p.id.to_s
  end





require 'sinatra'
require 'base64'
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
require './github'



  set :database_file, "./config/database.yml"
  enable :sessions
  set :session_secret, DB_SESSION_SECRET

  get '/' do
    session['access_token'] ||= ''
    if session['access_token'] != ''
      session['db_user_name'] = get_dropbox_client.account_info['display_name']
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
    redirect to Github.login
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
    res = Github.callback request
    session['gh_access_token'] = res['access_token']
    user = Github.user_info session['gh_access_token']
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
   res = Github.create_repo params["name"], session['gh_access_token']
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
	Github.delete_file f[0], @p
      elsif !f[1]["is_dir"]
	Github.update_file f[1]['path'], @p
      end
    end
    @p.touch
    redirect to '/projects/' + @p.id.to_s
  end

require 'sinatra'
require 'rest-client'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/activerecord'
require 'dropbox_sdk'
require 'pry'
require './env' if File.exists? 'env.rb'
require './models/user'

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
    @u.save
    redirect to '/'
  end








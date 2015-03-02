require 'sinatra'
require 'sinatra/base'
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
      @client = get_dropbox_client.account_info['display_name']
      @users = User.all
    end
    erb :index
  end

  def get_auth
    redirect_uri = DB_CALLBACK
    flow = DropboxOAuth2Flow.new( DB_APP_KEY, DB_APP_SECRET, redirect_uri, session, :dropbox_auth_csrf_token)
  end

  get '/login' do
    auth_url = get_auth.start
    redirect to auth_url
  end

  get '/logout' do
    session.delete(:access_token)
    redirect to '/'
  end

  def get_dropbox_client
    return DropboxClient.new(session[:access_token]) if session[:access_token]
  end

  get '/callback' do
    code = params[:code]
    access_token, user_id, url_state = get_auth.finish(params)
    u = User.find_or_create_by( db_uid: user_id )
    u.db_access_token = access_token
    u.save
    session['access_token'] = access_token
    redirect to '/'
  end
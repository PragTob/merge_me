require 'bundler/setup'
require 'sinatra'
require 'rest_client'
require 'json'

# !!! DO NOT EVER USE HARD-CODED VALUES IN A REAL APP !!!
# Instead, set and test environment variables, like below
# if ENV['GITHUB_CLIENT_ID'] && ENV['GITHUB_CLIENT_SECRET']
#  CLIENT_ID        = ENV['GITHUB_CLIENT_ID']
#  CLIENT_SECRET    = ENV['GITHUB_CLIENT_SECRET']
# end

CLIENT_ID = ENV['GH_CLIENT_ID']
CLIENT_SECRET = ENV['GH_SECRET_ID']
REQUIRED_SCOPES = %w(repo read:repo_hook write:repo_hook).join(",")
MY_URL = 'http://fa9893a0.ngrok.io'

p CLIENT_ID
p CLIENT_SECRET

use Rack::Session::Pool, :cookie_only => false

def authenticated?
  session[:access_token]
end

def authenticate!
  erb :'index.html', :locals => { :client_id => CLIENT_ID}
end

def access_token
  @access_token ||= session[:access_token]
end

get '/' do
  p request
  if !authenticated?
    authenticate!
  else
    scopes       = []

    begin
      auth_result = RestClient.get('https://api.github.com/user',
                                   {:params => {:access_token => access_token},
                                    :accept => :json})
    rescue => e
      # request didn't succeed because the token was revoked so we
      # invalidate the token stored in the session and render the
      # index page so that the user can start the OAuth flow again

      session[:access_token] = nil
      return authenticate!
    end

    # the request succeeded, so we check the list of current scopes
    if auth_result.headers.include? :x_oauth_scopes
      scopes = auth_result.headers[:x_oauth_scopes].split(', ')
    end

    auth_result = JSON.parse(auth_result)
    p auth_result
    p scopes
    p access_token

    if scopes.include? 'user:email'
      auth_result['private_emails'] =
        JSON.parse(RestClient.get('https://api.github.com/user/emails',
                                  {:params => {:access_token => access_token},
                                   :accept => :json}))
    end

    erb :'advanced.html', :locals => auth_result
  end
end

get '/callback' do
  session_code = request.env['rack.request.query_hash']['code']

  result = RestClient.post('https://github.com/login/oauth/access_token',
                           {:client_id => CLIENT_ID,
                            :client_secret => CLIENT_SECRET,
                            :code => session_code},
                           :accept => :json)

  session[:access_token] = JSON.parse(result)['access_token']

  redirect '/'
end

post '/webhook' do
  @payload = JSON.parse(params[:payload]) if params[:payload]
  p request
  puts '---------------'
  p @payload

  200
end

post '/create_hook' do
 response =  RestClient.post('https://api.github.com/repos/PragTob/merge_me-test/hooks',
                  {
                    name:         "web",
                    active:       true,
                    events:       ["status"],
                    config:       {
                      url:          "#{MY_URL}/webhook",
                      content_type: "json"
                    }
                  }.to_json,
                  accept: :json,
                  authorization: "token #{access_token}"
                  )
  p response
  redirect '/'
end

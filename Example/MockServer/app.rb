require 'rubygems'
require 'bundler'
Bundler.require

USERNAME = 'alice'
PASSWORD = 'secret'
SESSION_TTL_IN_SECONDS = 5

helpers do
  def session_filename(session_id)
    "session_#{session_id}"
  end
  
  def go_away!
    halt 401, { 'Content-Type' => 'application/json' },
      '{ "status": "401", "code": "401", "message": "Bad username or password" }'
  end
end

# To test:
# curl -iX POST -H "Content-type: application/json" -d '{ "username": "alice", "password": "secret" }' http://localhost:9292/login; echo
post '/login' do
  json = (JSON.parse(request.body.read.to_s) rescue halt 400)
  
  go_away! if json['username'] != USERNAME or json['password'] != PASSWORD
  
  session_id = 6.times.map { rand(16).to_s(16) }.join.upcase
  FileUtils.touch session_filename(session_id)
  
  response.set_cookie 'JSESSIONID', :value => session_id,
    :path => '/', :secure => true, :httponly => true
  status 200
  content_type :json
  body '{ "user_id": 123, "unread_notifications": 42 }'
end

# To test:
# curl -i --cookie 'JSESSIONID=<your_session_id_here>' http://localhost:9292/api_call; echo
get '/api_call' do
  session_id = request.cookies['JSESSIONID']
  go_away! if session_id.nil?
  
  if not File.exist? session_filename(session_id) or
      (Time.now - File.ctime(session_filename(session_id))) > SESSION_TTL_IN_SECONDS then
    halt 200, "Session expired"
  end
  
  status 200
  content_type :json
  body '{ "pets": ["cat", "horse", "cow"] }'
end

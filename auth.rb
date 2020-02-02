require 'sinatra/base'
require 'slack-ruby-client'

# load Slack app info into hash called `config` from env vars assigned during setup
SLACK_CONFIG = {
    slack_client_id: ENV['SLACK_CLIENT_ID'],
    slack_api_secret: ENV['SLACK_API_SECRET'],
    slack_redirect_uri: ENV['SLACK_REDIRECT_URI'],
    slack_verification_token: ENV['SLACK_VERIFICATION_TOKEN']
}

# check to see if required vars listed above were provided, raise exception if missing
missing_params = SLACK_CONFIG.select{ |key, value| value.nil? }
if missing_params.any?
    error_msg = missing_params.keys.join(", ").upcase
    raise "Missing Slack config variables: #{error_msg}"
end

# set OAuth scope of bot
# for this demo, we're just using `bot` as it has access to all we need
# see https://api.slack.com/docs/oauth-scopes for more info.
BOT_SCOPE = 'bot'

# this hash will contain all info for each authed team, as well as each team's Slack client object
# in production env, you may want to move some if this into a real data store
$teams = {}

# this helper keeps all logic in one place for creating Slack client objects for each team
def create_slack_client(slack_api_secret)
    Slack.configure do |config|
        config.token = slack_api_secret
        fail 'Missing API token' unless config.token
    end
    Slack::Web::Client.new
end

# Slack uses OAuth for user authentication.
# OAuth is performed by exchanging set of keys and tokens between Slack's servers and yours
# Process allows authoring user to confirm they want to grant bot access to team
# See https://api.slack.com/docs/oauth for more information.
class Auth < Sinatra::base
    # HTML markup for "Add to Slack" button
    # note we pass app-specific config params in!
    add_to_slack_button = %(
        <a href=\"https://slack.com/oauth/authorize?scope=#{BOT_SCOPE}&client_id=#{SLACK_CONFIG[:slack_client_id]}&redirect_uri=#{SLACK_CONFIG[:redirect_uri]}\">
          <img alt=\"Add to Slack\" height=\"40\" width=\"139\" src=\"https://platform.slack-edge.com/img/add_to_slack.png\"/>
        </a>
    )    
    
    # if user tires to access index page, redirect them to auth start page
    get '/' do
        redirect '/begin_auth'
    end

    # OAUTH STEP 1: Show the "Add to Slack" button, which links to Slack's auth request page.
    # this page show user what our app would like to access
    # and what bot user we'd like to create for their team
    get '/begin_auth' do
        status 200
        body add_to_slack_button
    end

    # OATH STEP 2: The user has told Slack that they want to authorize app to use their account,
    # so Slack sends us code which we can use to request a token for the user's account
    get '/finish_auth' do
        client = Slack::Web::Client.new

        # OATH STEP 3: Success or Failure
        begin
            response = client.oauth_access({
                    client_id: ENV['SLACK_CLIENT_ID'],
                    client_secret: ENV['SLACK_API_SECRET'],
                    redirect_uri: ENV['SLACK_REDIRECT_URI'],
                    code: params[:code] # this is the OAUTH code mentioned above
            })

            # SUCCESS: store tokens and create Slack client to use with Event Handlers
            # Tokens used for accessing web API, but process also creates team's bot user
            # and authorizes the app to access the team's event
            team_id = response['team_id']
            $teams[team_id] = {
                user_access_token: response['access_token'],
                bot_user_id: response['bot']['bot_user_id'],
                bot_access_token: response['bot']['bot_access_token']
            }

            $teams[team_id]['client'] = create_slack_client(response['bot']['bot_access_token'])
            
            # let user know auth succeeded
            status 200
            body "OAuth succeeded!"

        rescue Slack::Web::Api::Error => exception
            # FAILURE
            # let user know something went wrong
            status 403
            body "Auth failed! Reason: #{exception.message}<br/>#{add_to_slack_button}"
            
        end
    end
end

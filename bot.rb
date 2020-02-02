# Where all of the event logic lives.
# Where you'll find the handlers to actually process and respond to events.

require 'sinatra/base'
require 'slack-ruby-client'

# class contains all logic for loading, cloning, and updating tutorial message attachments
class SlackTutorial
    # store welcome text for use when sending and updating tutorial messages
    def self.welcome_text
        "Welcome to Slack! We're so glad you're here.\nGet started by completing the steps below."
    end

    # load tutorial JSON file into hash
    def self.tutorial_json
        tutorial_file = File.read('welcome.json')
        tutorial_json = JSON.parse(tutorial_file)
        attachments = tutorial_file['attachments']
    end

    # store index of each tutorial section in TUTORIAL_JSON for easy reference later
    def self.items
        { reaction: 0, pin: 1, share: 2}
    end
    
    # return new copy of tutorial_json so each user has their own instance
    def self.new
        self.tutorial_json.deep_dup
    end

    # helper fn to update state of tutorial items in hash shown above.
    # when user completes action on tutorial, item's icon will be set
    # to a green checkmark and the item's border color will be set to blue
    def self.update_item(team_id, user_id, item_index)
        # update tutorial section by replaciong the empty checkbox
        # with green checkbox and updating section's color to show it's completed
        tutorial_item = $team[team_id][user_id][:tutorial_content][item_index]
        tutorial_item['text'].sub!(':white_large_square', ':white_check_mark')
        tutorial_item['color'] = '#439FE0'
    end
end

# class contains all webserver logic for processing incoming requests from Slack
class API < Sinatra::Base 
    # this is endpoint Slack will post event data to
    post '/events' do
        # extract event payload from request and parse JSON
        request_data = JSON.parse(request.body.read)

        # The request contains a `type` attribute
        # which can be one of many things, in this case,
        # we only care about `url_verification` events.
        case request_data['type']
            when 'url_verification'
                # When we receive a `url_verification` event, we need to
                # return the same `challenge` value sent to us from Slack
                # to confirm our server's authenticity.
                request_data['challenge']

            when 'event_callback'
                # Get the Team ID and event data from the request object
                team_id = request_data['team_id']
                event_data = request_data['event']
        
                # Events have a "type" attribute included in their payload, allowing you to handle different
                # event payloads as needed.
                case event_data['type']
                    when 'url_verification'
                        # When we receive a `url_verification` event, we need to
                        # return the same `challenge` value sent to us from Slack
                        # to confirm our server's authenticity.
                        request_data['challenge']
                    
                    when 'team_join'
                        # Event handler for when a user joins a team
                        Events.user_join(team_id, event_data)
                    else
                        # In the event we receive an event we didn't expect, we'll log it and move on.
                        puts "Unexpected event:\n"
                        puts JSON.pretty_generate(request_data)
                end
                # Return HTTP status code 200 so Slack knows we've received the event
                status 200
        end

        # check verification token provided with request to make sure it matches
        # the verification token in app's setting to confirm that request came from Slack
        unless SLACK_CONFIG[:slack_verification_token] == request_data['token']
            halt 403, "Invalid Slack verification token received: #{request_data['token']}"
        end

        case request_data['type']
        # When you enter your Events webhook URL into your app's Event Subscription settings, Slack verifies the
        # URL's authenticity by sending a challenge token to your endpoint, expecting your app to echo it back.
        # More info: https://api.slack.com/events/url_verification
            when 'url_verification'
            request_data['challenge']

            when 'event_callback'
                # Get the Team ID and Event data from the request object
                team_id = request_data['team_id']
                event_data = request_data['event']

                # Events have a "type" attribute included in their payload, allowing you to handle different
                # Event payloads as needed.
                case event_data['type']
                    when 'team_join'
                    # Event handler for when a user joins a team
                    Events.user_join(team_id, event_data)
                    when 'reaction_added'
                    # Event handler for when a user reacts to a message or item
                    Events.reaction_added(team_id, event_data)
                    when 'pin_added'
                    # Event handler for when a user pins a message
                    Events.pin_added(team_id, event_data)
                    when 'message'
                    # Event handler for messages, including Share Message actions
                    Events.message(team_id, event_data)
                    when 'app_mention'
                    # Event handler for messages, including Share Message actions
                    puts "someone said something"
                    else
                    # In the event we receive an event we didn't expect, we'll log it and move on.
                    puts "Unexpected event:\n"
                    puts JSON.pretty_generate(request_data)
                end
                # Return HTTP status code 200 so Slack knows we've received the Event
                status 200
        end
    end
end

class Events
    # You may notice that user and channel IDs may be found in
    # different places depending on the type of event we're receiving.
  
    # A new user joins the team
    def self.user_join(team_id, event_data)
        user_id = event_data['user']['id']
        # Store a copy of the tutorial_content object specific to this user, so we can edit it
        $teams[team_id][user_id] = {
            tutorial_content: SlackTutorial.new
        }
        # Send the user our welcome message, with the tutorial JSON attached
        self.send_response(team_id, user_id)
    end
  
    # A user reacts to a message
    def self.reaction_added(team_id, event_data)
        user_id = event_data['user']
        if $teams[team_id][user_id]
            channel = event_data['item']['channel']
            ts = event_data['item']['ts']
            SlackTutorial.update_item(team_id, user_id, SlackTutorial.items[:reaction])
            self.send_response(team_id, user_id, channel, ts)
        end
    end
  
    # A user pins a message
    def self.pin_added(team_id, event_data)
        user_id = event_data['user']
        if $teams[team_id][user_id]
            channel = event_data['item']['channel']
            ts = event_data['item']['message']['ts']
            SlackTutorial.update_item(team_id, user_id, SlackTutorial.items[:pin])
            self.send_response(team_id, user_id, channel, ts)
        end
    end
  
    def self.message(team_id, event_data)
        user_id = event_data['user']
        # Don't process messages sent from our bot user
        unless user_id == $teams[team_id][:bot_user_id]

            # This is where our `message` event handlers go:

            # INCOMING GREETING
            # We only care about message events with text and only if that text contains a greeting.
            if event_data['text'] && event_data['text'].scan(/hi|hello|greetings/i).any?
                # If the message does contain a greeting, say "Hello" back to the user.
                $teams[team_id]['client'].chat_postMessage(
                    as_user: 'true',
                    channel: user_id,
                    text: "Hello <@#{user_id}>!"
                )
            end
    
            # SHARED MESSAGE EVENT
            # To check for shared messages, we must check for the `attachments` attribute
            # and see if it contains an `is_shared` attribute.
            if event_data['attachments'] && event_data['attachments'].first['is_share']
                # We found a shared message
                user_id = event_data['user']
                ts = event_data['attachments'].first['ts']
                channel = event_data['channel']
                # Update the `share` section of the user's tutorial
                SlackTutorial.update_item( team_id, user_id, SlackTutorial.items[:share])
                # Update the user's tutorial message
                self.send_response(team_id, user_id, channel, ts)
            end
        end
    end
  
    # Send a response to an Event via the Web API.
    def self.send_response(team_id, user_id, channel = user_id, ts = nil)
        # `ts` is optional, depending on whether we're sending the initial
        # welcome message or updating the existing welcome message tutorial items.
        # We open a new DM with `chat.postMessage` and update an existing DM with
        # `chat.update`.
        if ts
            $teams[team_id]['client'].chat_update(
            as_user: 'true',
            channel: channel,
            ts: ts,
            text: SlackTutorial.welcome_text,
            attachments: $teams[team_id][user_id][:tutorial_content]
            )
        else
            $teams[team_id]['client'].chat_postMessage(
            as_user: 'true',
            channel: channel,
            text: SlackTutorial.welcome_text,
            attachments: $teams[team_id][user_id][:tutorial_content]
            )
        end
    end
  
end

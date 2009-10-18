#!/usr/bin/env ruby
#
# Purpose: start the bot and keep it alive

begin
  require "rubygems"
  require "eventmachine"
  require "xmpp4r-simple"
  require "json"
  require "sequel"
  require "myconfig"
  require "global"
#  require "plugins"
rescue LoadError
  puts "[E] --- json, sequel, eventmachine, xmpp4r-simple are required ---"
  exit
end

DB = Sequel.connect("sqlite://#{PaaS::DB_FILE}")

unless DB.table_exists? "users"
  DB.create_table :users do
    primary_key :id
    varchar :jid

    varchar :nick
    varchar :name

    time    :created

    index   [:created]
    index   [:nick], :unique => true
    index   [:jid], :unique => true
  end
end

unless DB.table_exists? "presences"
  DB.create_table :presences do
    primary_key :id
    foreign_key :user_id

    varchar :status, :default => 'unknown'
    varchar :message, :default => ''
    time    :created, :default => Time.now

    index   [:status]
    index   [:created]
  end
end


# from github-services
# Jabber::Simple does some insane kind of queueing if it thinks
# # we are not in their buddy list (which is always) so messages
# # never get sent before we disconnect. This forces the library
# # to assume the recipient is a buddy.
class Jabber::Simple
  def subscribed_to?(x); true; end
  def ask_for_auth(x); contacts(x).ask_for_authorization!; end
end


module PaaS

  class Bot

    def self.help
      body = "\n#{NAME} v#{VERSION}\nCommands:\n"
      body += "HELP, H, help, ? : List all local commands\n"
      body += "PING, P, ping : Connection test\n"
      body += "STAT[US], S, stat[us] [JID] : get JID status - 'away' etc.\n"
      body += "LOGIN, L, login : register in the system\n"
      body += "NICK, N, nick [name] : change/show your nick (2-16 chars, [A-Za-z0-9_])\n"
      body
    end

    def self.announce(subscribers, messages)
      return unless @@xmpp
      Array(subscribers).each do |to|
        Array(messages).each do |body|
          @@xmpp.deliver(to, body)
        end
      end
    end

    def self.run
      @@xmpp = Jabber::Simple.new(USER, PASS)
      @@master = MASTERS[0]

      # Accept any friend request
      @@xmpp.accept_subscriptions = true
      at_exit { @@xmpp.status(:away, "cya") }

      EM.epoll   # Only on Linux 2.6.x
      EM.run do

        EM::PeriodicTimer.new(5) do

          @@xmpp.presence_updates do |u, s, m|
            p "presence: user=#{u} status=#{s} msg=#{m}"
            msg = (not m or m.empty?) ? s : m
            
            begin
              user = DB[:users].filter(:jid => u.to_s).first
              if not user
                DB[:users] << { :jid => u.to_s, :nick => u.to_s, :created => Time.now }
                user = DB[:users].filter(:jid => u.to_s).first
                p "new user: #{u.to_s}"
              end
              # TODO: keep last ... presences in memcached
              prev = DB[:presences].filter(:user_id => user[:id]).order(:created).last
              if not prev or prev[:status] != s.to_s or prev[:message] != m.to_s
                p "#{prev[:status]} (#{prev[:message]}) -> #{s.to_s} (#{m.to_s})" if prev
                DB[:presences] << { :user_id => user[:id], 
                                    :status => s.to_s, 
                                    :message => m.to_s, 
                                    :created => Time.now }
              end  
            rescue 
              next
            end  
          end

        end


        EM::PeriodicTimer.new(0.05) do

          @@xmpp.received_messages do |msg|
            # process only non-empty chat messages
            next unless (msg.type == :chat and not msg.body.empty?)

            from = msg.from.strip.to_s
            cmdline = msg.body.split
            
            case cmdline[0]
            when "HELP", "H", "help", "?":
              Bot.announce(from, [Bot.help])
            when "PING", "P", "ping":
              Bot.announce(from, "PONG")
            when "LOGIN", "L", "login":
              @@xmpp.ask_for_auth(msg.from)
              Bot.announce(from, "Please accept the authorization request.")
            when "NICK", "N", "nick":
              begin
                user = DB[:users].filter(:jid => from)
                exists = DB[:users].filter(:nick => cmdline[1]).first
                if cmdline[1] and cmdline[1].valid_nick? and not exists
                  user.update(:nick => cmdline[1])
                end
                Bot.announce(from, "Nick: #{user.first[:nick]}")
              rescue
                Bot.announce(from, "Nick: unknown")
              end
            when "STATUS", "STAT", "S", "status", "stat":
              begin
                if cmdline[1]
                  user = DB[:users].filter(:nick => cmdline[1]).first
                else
                  user = DB[:users].filter(:jid => from).first
                end
                presence = DB[:presences].filter(:user_id => user[:id]).order(:created).last
                text = "#{user[:nick]}'s status: #{presence[:status]}"
                text += " (#{presence[:message]})"  unless presence[:message].empty?
                Bot.announce(from, text)
              rescue 
                Bot.announce(from, "status: unknown")
                next
              end
            else
              next unless MASTERS.include?(from)
              # some commands, available only for the admins
            end
          end  
        end
      end
    end
  end  
end  

if __FILE__ == $0
  trap("INT") { EM.stop }
  PaaS::Bot.run
end  

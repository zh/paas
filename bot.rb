#!/usr/bin/env ruby
#
# Purpose: start the bot and keep it alive

begin
  require "rubygems"
  require "eventmachine"
  require "xmpp4r-simple"
  require "json"
  require "sequel"
  require "httpclient"
  require "myconfig"
  require "global"
rescue LoadError
  puts "[E] --- json, sequel, eventmachine, xmpp4r-simple are required ---"
  exit
end

begin
  require 'system_timer'
  MyTimer = SystemTimer
rescue
  require 'timeout'
  MyTimer = Timeout
end

DB = Sequel.connect("sqlite://#{PaaS::DB_FILE}")

unless DB.table_exists? "users"
  DB.create_table :users do
    primary_key :id
    varchar :jid

    varchar :nick
    boolean :quiet,  :default => false  # trac only XA presences
    boolean :push,   :default => false  # PuSH publish

    time    :registered

    index   [:registered]
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

  class Task
    include EM::Deferrable

    def do_publish(user)
      query = { 'hub.mode' => 'publish',
                'hub.url'  => "#{PaaS::HTTPBASE}atom/#{user[:nick]}" }
      begin
        MyTimer.timeout(5) do
          res = HTTPClient.get(PaaS::PUSHUB, query)
          status = res.status.to_i
          raise "do_verify(#{user[:nick]})" if (status < 200 or status >= 300)
        end
        sleep(0.05)
        set_deferred_status(:succeeded)
      rescue Exception => e
        puts e.to_s
        set_deferred_status(:failed)
      end
    end

    def do_send(args = {})
      begin
        raise "Missing arguments for do_send()" unless (args[:jid] and args[:message])
        Bot.announce(args[:jid], [args[:message]])
        sleep(0.05)
        set_deferred_status(:succeeded)
      rescue Exception => e
        puts e.to_s
        set_deferred_status(:failed)
      end
    end
  end

  class Bot

    def self.help
      body = "\n#{NAME} v#{VERSION}\nCommands:\n"
      body += "HELP, H, help, ? : List all local commands\n"
      body += "PING, P, ping : Connection test\n"
      body += "LOGIN, L, login : register in the system\n"
      body += "ONLINE, O, online : Online users list\n"
      body += "STAT[US], S, stat[us] [JID] : get JID status - 'away' etc.\n"
      body += "NICK, N, nick [name] : change/show your nick (2-16 chars, [A-Za-z0-9_])\n"
      body += "MSG, M, msg {nick} {text} : Direct message {text} to user {nick}\n"
      body += "ON/OFF, on/off : Enable/disable presences sharing\n"
      body += "QUIET/VERBOSE, quiet/verbose : Trac all or only XA presences\n"
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

    def self.run(options)
      puts "run options: #{options.inspect}" if PaaS::DEBUG

      @@xmpp = Jabber::Simple.new(USER, PASS)
      @@master = MASTERS[0]

      # Accept any friend request
      @@xmpp.accept_subscriptions = true
      at_exit { @@xmpp.status(:away, "cya") }

      EM.epoll   # Only on Linux 2.6.x
      EM.run do
        if options[:with_api] == true
          puts "starting web API on port #{options[:port]}..." if PaaS::DEBUG
          require 'api'
          PaaS::App.run!(:port => options[:port])
        end  

        EM::PeriodicTimer.new(5) do

          @@xmpp.presence_updates do |u, s, m|
            p "presence: user=#{u} status=#{s} msg=#{m}" if PaaS::DEBUG
            msg = (not m or m.empty?) ? s : m
            
            begin
              user = DB[:users].filter(:jid => u.to_s).first
              if not user
                DB.transaction do
                  DB[:users] << { :jid => u.to_s, :nick => u.to_s, :registered => Time.now }
                  user = DB[:users].filter(:jid => u.to_s).first
                  p "new user: #{u.to_s}" if PaaS::DEBUG
                end
              end
              # TODO: keep last ... presences in memcached
              prev = DB[:presences].filter(:user_id => user[:id]).order(:created).last
              if not prev or prev[:status] != s.to_s or prev[:message] != m.to_s
                # trac only XA presences in quiet mode
                next if (user[:quiet] and s.to_s != 'xa')
                if prev and PaaS::DEBUG
                  p "#{prev[:status]} (#{prev[:message]}) -> #{s.to_s} (#{m.to_s})"
                end
                DB.transaction do
                  DB[:presences] << { :user_id => user[:id], 
                                      :status => s.to_s, 
                                      :message => m.to_s, 
                                      :created => Time.now }
                end
                # ping the PuSH hub
                if user[:push]
                  EM.spawn do
                    task = Task.new
                    task.callback { p "sucess: #{user[:nick]}" if PaaS::DEBUG }
                    task.errback { p "fail: #{user[:nick]}" if PaaS::DEBUG }
                    task.do_publish(user)
                  end.notify
                end
              end  
            rescue 
              next
            end  
          end

        end

        # send presence every minute
        EM::PeriodicTimer.new(60) do
          @@xmpp.status(nil, "Available")
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
            when "ON", "OFF", "on", "off":
              begin
                mode = ""
                DB.transaction do
                  user = DB[:users].filter(:jid => from)
                  mode = (cmdline[0].downcase == 'on') ? true : false
                  user.update(:push => mode)
                end 
                Bot.announce(from, "Sharing (PuSH): #{mode}")
              rescue
                Bot.announce(from, "Not implemented")
              end
            when "QUIET", "VERBOSE", "quiet", "verbose":
              begin
                mode = ""
                DB.transaction do
                  user = DB[:users].filter(:jid => from)
                  mode = (cmdline[0].downcase == 'quiet') ? true : false
                  user.update(:quiet => mode)
                end 
                Bot.announce(from, "Trac only XA: #{mode}")
              rescue
                Bot.announce(from, "Not implemented")
              end
            when "ONLINE", "O", "online":
              list = "Online users:\n"
              # last presences for every user
              DB[:presences].order(:created.desc).group(:user_id).each do |p|
                if p[:status] == 'online'
                  user = DB[:users].filter(:id => p[:user_id]).first
                  list += user[:nick]
                  list += " : #{p[:message]}" unless p[:message].empty?
                  if user[:push] or user[:quiet]
                    list += " ["
                    list += " sharing" if user[:push]
                    list += " quiet" if user[:quiet]
                    list += " ]"
                  end
                  list += " #{Time.parse(p[:created].to_s).time_since(Time.now)} ago\n"
                end
              end
              Bot.announce(from, [list])
            when "NICK", "N", "nick":
              begin
                user = DB[:users].filter(:jid => from)
                exists = DB[:users].filter(:nick => cmdline[1]).first
                if cmdline[1] and cmdline[1].valid_nick? and not exists
                  DB.transaction do
                    user.update(:nick => cmdline[1])
                  end
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
                if user[:push] or user[:quiet]
                  text += " ["
                  text += " sharing" if user[:push]
                  text += " quiet" if user[:quiet]
                  text += " ]"
                end
                text += " #{Time.parse(presence[:created].to_s).time_since(Time.now)} ago"
                Bot.announce(from, text)
              rescue 
                Bot.announce(from, "status: unknown")
                next
              end
            when "MSG", "M", "msg":
              begin
                raise "missing arguments" unless cmdline.length > 2
                user = DB[:users].filter(:jid => from).first
                args = {}
                args[:jid] = DB[:users].filter(:nick => cmdline[1]).first[:jid]
                args[:message]  = "message from #{user[:nick]}:\n" 
                args[:message] += msg.body.sub(cmdline[0],"").sub(cmdline[1],"").strip
                EM.spawn do
                  task = Task.new
                  task.callback { Bot.announce(from, "message to '#{cmdline[1]}' sent") }
                  task.errback { raise "do_send() error" }
                  task.do_send(args)
                end.notify
              rescue Exception => e 
                Bot.announce(from, "message not sent: #{e.to_s}")
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
  options = { :port => PaaS::API_PORT, :with_api => false }
  if ARGV.any?
    require 'optparse'
    OptionParser.new { |op|
      op.on('-a')      { |val| options[:with_api] = true }
      op.on('-p port') { |val| options[:port] = val.to_i }
    }.parse!(ARGV.dup)
  end
  PaaS::Bot.run(options)
end  

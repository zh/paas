#!/usr/bin/env ruby

require 'time'
require 'rubygems'
require 'sinatra'
require 'sequel'
require 'zlib'
require 'digest/sha1'
require 'json'
require 'atom/pub'
require 'xmpp4r'
require 'xmpp4r/vcard'
require 'myconfig'
require 'global'

module PaaS

  class App < Sinatra::Default
  
    set :sessions, false
    set :run, false
    set :environment, ENV['RACK_ENV']
  
    configure do
      DB = Sequel.connect(ENV['DATABASE_URL'] || "sqlite://#{PaaS::DB_FILE}")

      # user by JID or nick
      def param2user(nick_or_jid)
        if nick_or_jid.include?('@')
          user = DB[:users].filter(:jid => nick_or_jid).first
        else
          user = DB[:users].filter(:nick => nick_or_jid).first
        end
        user
      end
    end

    get '/photo/:nick_or_jid/?' do
      begin
        user = param2user(params[:nick_or_jid])
        client = Jabber::Client.new(Jabber::JID.new(PaaS::USER))
        client.connect
        client.auth(PaaS::PASS)
        vcard = Jabber::Vcard::Helper.new(client).get(user[:jid])
        type = vcard['PHOTO/TYPE']
        if type
          content_type type
          return vcard.photo_binval
        else
          raise "no vcard photo set"
        end
      rescue
        content_type 'image/png'
        File.open(File.join("public","images","nobody.png"))
      end
    end

    get '/last/:nick_or_jid/:type/?' do
      content_type 'application/json; charset=utf-8'
      begin
        user = param2user(params[:nick_or_jid])
        presence = DB[:presences].filter(:user_id => user[:id]).order(:created).last
        if params[:type] == 'image'
          content_type 'image/png'
          fname = STATUS.include?(presence[:status]) ? presence[:status] : "unknown"
          File.open(File.join("public","images","#{fname}.png"))
        else
          tm = presence[:created].to_s
          text = {
            :time => Time.parse(tm).getgm.strftime("%Y-%m-%dT%H:%M:%SZ"),
            :since => Time.parse(tm).time_since(Time.now),
            :status => presence[:status]
          }
          text[:message] = presence[:message] unless presence[:message].empty?
          text.to_json
        end
      rescue
        if params[:type] == 'image'
          content_type 'image/png'
          File.open(File.join("public","images","unknown.png"))
        else
          text = {
            :time => Time.now.getgm.strftime("%Y-%m-%dT%H:%M:%SZ"),
            :since => Time.now.time_since(Time.now),
            :status => "unknown"
          }.to_json
        end
      end
    end

    get '/atom/:nick_or_jid/?' do
      begin
        user = param2user(params[:nick_or_jid])
        content_type 'application/atom+xml', :charset => 'utf-8'
        # cache for 30 sec
        headers 'Cache-Control' => 'max-age=30, public',
                'Expires' => (Time.now + 30).httpdate
        feed = Atom::Feed.new do |f|
          f.title   = "#{params[:nick_or_jid]}'s presences feed"
          f.id      = "urn:uuid:"+Digest::SHA1.hexdigest("--#{PaaS::HTTPBASE}--#{PaaS::SALT}")
          if DB[:presences].count > 0
            tm = Time.parse(DB[:presences].order(:created.desc).last[:created].to_s)
          else
            tm = Time.now
          end
          f.updated = tm.getgm.strftime("%Y-%m-%dT%H:%M:%SZ")
          f.authors << Atom::Person.new(:name => params[:nick_or_jid])
          f.links  << Atom::Link.new(:rel=>"self",
                                     :href=>"#{PaaS::HTTPBASE}atom/#{params[:nick_or_jid]}",
                                     :type=>"application/atom+xml")
          f.links  << Atom::Link.new(:rel => 'alternate',
                                     :href => "#{PaaS::HTTPBASE}user/#{user[:nick]}")
          f.links  << Atom::Link.new(:rel => 'hub',
                                     :href => PaaS::PUSHUB)
          DB[:presences].where(:user_id => user[:id]).order(:created.desc).limit(PaaS::FEED_PAGE).each do |p|
            guid = Digest::SHA1.hexdigest("--#{p[:id]}--#{PaaS::SALT}")
            f.entries << Atom::Entry.new do |e|
              e.id         = "urn:uuid:#{guid}"
              e.authors   << Atom::Person.new(:name => params[:nick_or_jid])
              e.title      = p[:status]
              e.updated    = p[:created]
              e.published  = p[:created]
              e.links     << Atom::Link.new(:rel => 'alternate', 
                                    :href => "#{PaaS::HTTPBASE}last/#{params[:nick_or_jid]}/text")
              e.content    = p[:message].empty? ? p[:status] : p[:message]
            end
          end
        end
        feed.to_xml
      rescue
        throw :halt, [404, "Not Found"]
      end
    end

    
    get '/json' do
      content_type 'application/json; charset=utf-8'
      # cache for 30 sec.
      headers 'Cache-Control' => 'max-age=30, public',
              'Expires' => (Time.now + 30).httpdate
      list = []
      DB[:presences].order(:created.desc).limit(PaaS::PAGE).each do |p|
        user = DB[:users].filter(:id => p[:user_id]).first
        if user
          tm = Time.parse(p[:created].to_s)
          list << { :nick => user[:nick], 
                    :status => p[:status], 
                    :message => p[:message], 
                    :time => tm.to_formatted_s(:rfc822),
                    :since => tm.time_since(Time.now) }
        end
      end
      js = list.to_json
      # Allow 'abc' and 'abc.def' but not '.abc' or 'abc.'
      if params[:callback] and params[:callback].match(/^\w+(\.\w+)*$/)
        js = "#{params[:callback]}(#{js})"
      end
      js
    end


    # mostly for demo purposes
    get '/' do
      headers 'Cache-Control' => 'max-age=120, public',
              'Expires' => (Time.now + 120).httpdate
      erb :index
    end

    get '/user/:nick/?' do
      begin
       headers 'Cache-Control' => 'max-age=120, public',
               'Expires' => (Time.now + 120).httpdate
        @user = DB[:users].filter(:nick => params[:nick]).first
        @presences = DB[:presences].where(:user_id => @user[:id]).order(:created.desc).limit(PaaS::PAGE)
        erb :user
      rescue
        throw :halt, [404, "Not Found"]
      end
    end

  end
end

if __FILE__ == $0
  PaaS::App.run!
end

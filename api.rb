#!/usr/bin/env ruby

require 'time'
require 'rubygems'
require 'sinatra'
require 'sequel'
require 'zlib'
require 'digest/sha1'
require 'json'
require 'atom/pub'
require 'myconfig'
require 'global'

module PaaS

  class App < Sinatra::Default
  
    set :sessions, false
    set :run, false
    set :environment, ENV['RACK_ENV']
  
    configure do
      DB = Sequel.connect(ENV['DATABASE_URL'] || "sqlite://#{PaaS::DB_FILE}")
    end

    get '/last/:nick/:type/?' do
      begin
        user = DB[:users].filter(:nick => params[:nick]).first
        presence = DB[:presences].filter(:user_id => user[:id]).order(:created).last
        if params[:type] == 'image'
          content_type 'image/png'
          fname = STATUS.include?(presence[:status]) ? presence[:status] : "unknown"
          File.open(File.join("public","images","#{fname}.png"))
        else
          content_type 'application/json; charset=utf-8'
          tm = presence[:created].to_s
          text = {
            :time => Time.parse(tm).getgm.strftime("%Y-%m-%dT%H:%M:%SZ"),
            :status => presence[:status]
          }
          text[:message] = presence[:message] unless presence[:message].empty?
          text.to_json
        end
      rescue
        throw :halt, [404, "Not Found"]
      end
    end

    get '/atom/:nick/?' do
      begin
        user = DB[:users].filter(:nick => params[:nick]).first
        content_type 'application/atom+xml', :charset => 'utf-8'
        # cache for 30 sec
        headers 'Cache-Control' => 'max-age=30, public',
                'Expires' => (Time.now + 30).httpdate
        feed = Atom::Feed.new do |f|
          f.title   = "#{params[:nick]}'s presences feed"
          f.id      = "urn:uuid:"+Digest::SHA1.hexdigest("--#{PaaS::HTTPBASE}--#{PaaS::SALT}")
          if DB[:presences].count > 0
            tm = Time.parse(DB[:presences].order(:created.desc).last[:created].to_s)
          else
            tm = Time.now
          end
          f.updated = tm.getgm.strftime("%Y-%m-%dT%H:%M:%SZ")
          f.authors << Atom::Person.new(:name => params[:nick])
          f.links  << Atom::Link.new(:rel=>"self",
                                     :href=>"#{PaaS::HTTPBASE}atom/#{params[:nick]}",
                                     :type=>"application/atom+xml")
          f.links  << Atom::Link.new(:rel => 'alternate',
                                     :href => "#{PaaS::HTTPBASE}nick/#{params[:nick]}")
          f.links  << Atom::Link.new(:rel => 'hub',
                                     :href => PaaS::PUSHUB)
          DB[:presences].where(:user_id => user[:id]).order(:created.desc).limit(PaaS::FEED_PAGE).each do |p|
            guid = Digest::SHA1.hexdigest("--#{p[:id]}--#{PaaS::SALT}")
            f.entries << Atom::Entry.new do |e|
              e.id         = "urn:uuid:#{guid}"
              e.authors   << Atom::Person.new(:name => params[:nick])
              e.title      = p[:status]
              e.updated    = p[:created]
              e.published  = p[:created]
              e.links     << Atom::Link.new(:rel => 'alternate', 
                                    :href => "#{PaaS::HTTPBASE}last/#{params[:nick]}/text")
              e.content    = p[:message].empty? ? p[:status] : p[:message]
            end
          end
        end
        feed.to_xml
      rescue Exception => e
        p e.to_s
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

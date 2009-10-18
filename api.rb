#!/usr/bin/env ruby

require 'time'
require 'rubygems'
require 'sinatra'
require 'sequel'
require 'zlib'
require 'json'
require 'builder'
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

    get '/last/:nick/?' do
      begin
        user = DB[:users].filter(:nick => params[:nick]).first
        presence = DB[:presences].filter(:user_id => user[:id]).order(:created).last
        tm = presence[:created].to_s
        text = {
          :time => Time.parse(tm).getgm.strftime("%Y-%m-%dT%H:%M:%SZ"),
          :status => presence[:status]
        }
        text[:message] = presence[:message] unless presence[:message].empty?
        text.to_json
      rescue
        throw :halt, [404, "Not Found"]
      end
    end

    # TODO: Atom format + link + guid
    get '/feed/:nick/?' do
      begin
        user = DB[:users].filter(:nick => params[:nick]).first
        builder do |xml|
          xml.instruct! :xml, :version => '1.0'
          xml.rss :version => "2.0" do
            xml.channel do
              xml.title "#{params[:nick]}'s presences"
              xml.description "XMPP presences feed."
              xml.link "http://pass.heroku.com/"
        
              DB[:presences].where(:user_id => user[:id]).order(:created.desc).limit(10).each do |p|
                xml.item do
                  xml.title p[:status]
                  xml.description p[:message].empty? ? p[:status] : p[:message] 
                  xml.pubDate Time.parse(p[:created].to_s).rfc822()
                end
              end
            end
          end
        end
      rescue Exception => e
        p e.to_s
        throw :halt, [404, "Not Found"]
      end
    end

  end
end

if __FILE__ == $0
  PaaS::App.run!
end

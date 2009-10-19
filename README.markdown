## What is PaaS

[Presence-As-A-Service (PaaS)](http://status.zhware.net/) is using [XMPP presence stanzas](http://xmpp.org/rfcs/rfc3921.html#presence) for microblogging, online status displaying etc.


## Why?

 * Because [Google XMPP implementation sucks](http://code.google.com/appengine/docs/python/xmpp/overview.html#Google_Talk_User_Status)
 * Because XMPP presences are uncomplete ([missing timestamp](http://www.process-one.net/en/blogs/article/timestamp_on_presence_tag/))
 * Need it for other services ([ReaTiWe](http://reatiwe.appspot.com/))


## How?

### Install

 * Needed gems: eventmachine, xmpp4r-simple, json, ratom, httpclient, sequel, sinatra
 * Copy __myconfig.rb.dist__ to __myconfig.rb__ and adjust your settings
 * Start the bot (this will create also database [sqlite3], if missing):  __ruby ./bot.rb__
 * Start the API:
  * via [rackup](http://wiki.github.com/rack/rack/tutorial-rackup-howto): __rackup -p 8080__
  * standalone: __ruby ./api.rb -p 8080__

### Usage

 * Add the bot to your roster
 * __PING__ to test the connection
 * __HELP__ to see the available bot commands
 * Send __LOGIN__ command to register (and accept the authorization request)
 * Change your nick - __NICK ...__ to hide your real JID
 * Enable PuSH publishing - __ON__
 * All your presence changes will be saved - time, status, message
 * To trac only some presences (extended away - XA) - __QUIET__


## What you've get?

### Web (HTTP services)

 * __/last/:nick/:type__ - Text/image (.png) user status (status, message, timestamp)
 * __/atom/:nick__ - Atom feed with latest 10 presences (pinging PuSH hub on update)
 * __/json__ (optional __?callback=...__ parameter) JSON/JSONP with latest 10 presences
 * __/stream__ and __/user/:nick__ - demo services

### XMPP (bot commands)

 * __HELP, H, help, ?__ : List all local commands
 * __PING, P, ping__ : Connection test
 * __ONLINE, O, online__ : Online users list
 * __ON/OFF, on/off__ : Enable/disable presences sharing
 * __QUIET/VERBOSE, quiet/verbose__ : Trac all or only XA presences
 * __STAT[US], S, stat[us] [JID]__ : get JID status - 'away' etc.
 * __LOGIN, L, login__ : register in the system
 * __NICK, N, nick [name]__ : change/show your nick (2-16 chars, [A-Za-z0-9_])

You can make your own install, or use the __status@zhware.net_ bot and [http://status.zhware.net/](http://status.zhware.net/) URL for API calls and to see the results.

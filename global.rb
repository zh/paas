# Some core classes extensions

# unicode magic
$KCODE = 'u'
require 'jcode'
require 'open-uri'

class String
  # return first 'limit' characters from the string
  # NOTE: or u_slice() is better?
  def truncate(limit = 77)
    self.match(%r{^(.{0,#{limit}})})[1]
  end 

  def html_escape
    gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
  end

  # Encodes a normal string to a URI string.
  def uri_escape
    gsub(/([^ a-zA-Z0-9_.-]+)/n) {'%'+$1.unpack('H2'*$1.size).join('%').upcase}.tr(' ', '+')
  end

  # Decodes a URI string to a normal string.
  def uri_unescape
    tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n){[$1.delete('%')].pack('H*')}
  end

  def strip_tags
    gsub(/<.+?>/,'').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').
      gsub(/&ellip;/,'...').gsub(/&apos;/, "'")
  end

  def valid_nick?
    return false if self.length < 2 or self.length > 16 # 2-16 chars
    return false if self.include?('@')                  # @ means full JID
    return false if self =~ /\d+/                       # not only digits
    return false unless self =~ /\w+/                   # [A-Za-z0-9_]
    true
  end
end

class Time

  DATE_FORMATS = {
    :db     => "%Y-%m-%d %H:%M:%S",
    :short  => "%d %b %H:%M",
    :long   => "%B %d, %Y %H:%M",
    :rfc822 => "%a, %d %b %Y %H:%M:%S %z",
    :custom => "%H:%M %d %b %Y JST"
  }

  def to_formatted_s(format = :default)
    DATE_FORMATS[format] ? strftime(DATE_FORMATS[format]).strip : to_s
  end

  def time_since(from_time, include_seconds = false)
      distance_in_minutes = (((self - from_time).abs)/60).round
      distance_in_seconds = ((self - from_time).abs).round

      case distance_in_minutes
        when 0..1
          return (distance_in_minutes == 0) ? 'less than a minute' : '1 minute' unless include_seconds
          case distance_in_seconds
            when 0..4   then 'less than 5 seconds'
            when 5..9   then 'less than 10 seconds'
            when 10..19 then 'less than 20 seconds'
            when 20..39 then 'half a minute'
            when 40..59 then 'less than a minute'
            else             '1 minute'
          end

        when 2..44           then "#{distance_in_minutes} minutes"
        when 45..89          then 'about 1 hour'
        when 90..1439        then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
        when 1440..2879      then '1 day'
        when 2880..43199     then "#{(distance_in_minutes / 1440).round} days"
        when 43200..86399    then 'about 1 month'
        when 86400..525959   then "#{(distance_in_minutes / 43200).round} months"
        when 525960..1051919 then 'about 1 year'
        else                      "over #{(distance_in_minutes / 525960).round} years"
      end
  end
end

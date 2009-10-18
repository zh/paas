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

%w[open3 daemons socket singleton open-uri cgi pathname hpricot yaml net/https].map{|s| require s}

=begin rdoc
Run <tt>kirby.rb [nick] [channel] [server] [delicious_name] [delicious_password]</tt>. 

Optional parameters:
<tt>-d</tt>:: Daemonize.
<tt>-no-d</tt>:: Don't daemonize.
<tt>--silent</tt>:: Never speak, even for errors.

In-channel commands:
<tt>>> [string of code]</tt>:: Evaluate some Ruby code.
<tt>reset_irb</tt>:: Reset the <tt>irb</tt> session.
<tt>add_svn [repository_url]</tt>:: Watch an svn repository for changes.
=end

class Kirby
  include Singleton

  PATH = Pathname.new(".").dirname.realpath.to_s
  STORE = PATH + '/kirby.repositories'
  PIDFILE = PATH + '/kirby.pid'
  
  NICK = (ARGV[1] or "kirby-dev")
  CHANNEL = ("#" + (ARGV[2] or "kirby-dev"))
  SERVER = (ARGV[3] or "irc.freenode.org")
  DELICIOUS_USER, DELICIOUS_PASS = ARGV[4], ARGV[5]
  SILENT = ARGV[6] == "--silent"
  
  # Connect and reconnect to the server  
  def restart
    $store = (YAML.load_file STORE rescue {})
    @socket.close if @socket
    connect
    listen
  end
  
  # Connect to the IRC server.
  def connect
    @socket = TCPSocket.new(SERVER, 6667)
    write "USER #{[NICK]*3*" "} :#{NICK}"
    write "NICK #{NICK}"
    write "JOIN #{CHANNEL}"
  end
  
  private
  
  # The event loop. Waits for socket traffic, and then responds to it. The server sends <tt>PING</tt> every 3 minutes, which means we don't need a separate thread to check for svn updates. All we do is wake on ping (or channel talking).
  def listen
    @socket.each do |line|
#      puts "GOT: #{line.inspect}"
      poll unless SILENT
      case line.strip
        when /^PING/ then write line.sub("PING", "PONG")[0..-3]
        when /^ERROR/, /KICK #{CHANNEL} #{NICK} / then restart unless line =~ /PRIVMSG/
        else 
          if msg = line[/ PRIVMSG #{CHANNEL} \:(.+)/, 1]
            case msg
              when /^>>\s*(.+)/ then try $1.chop
              when /^#{NICK}/ then say "Usage: '>> CODE'. Say 'reset_irb' for a clean session. Say 'add_svn [repository_url]' to watch an svn repository."
              when /^reset_irb/ then reset_irb
              when /^add_svn (.+?)(\s|\r|\n|$)/ then $store[$1] = 0 and say $store.inspect
            end unless SILENT
            post($1) if DELICIOUS_PASS and msg =~ /(http:\/\/.*?)(\s|\r|\n|$)/ 
          end
      end
    end
  end
  
  # Send a raw string to the server.
  def write s
    raise RuntimeError, "No socket" unless @socket
    @socket.puts s += "\r\n"
#    puts "WROTE: #{s.inspect}"
  end
  
  # Eval a piece of code in the <tt>irb</tt> environment.
  def try s
    reset_irb unless $session
    try_eval(s).select{|e| e !~ /^\s+from .+\:\d+(\:|$)/}.each {|e| say e} rescue say "session error"
  end
  
  # Say something in the channel.
  def say s
    write "PRIVMSG #{CHANNEL} :#{s[0..450]}"
    sleep 1
  end
    
  # Get a new <tt>irb</tt> session.
  def reset_irb
    say "Began new irb session"
    $session = try_eval("!INIT!IRB!")
  end
  
  # Inner loop of the try method.
  def try_eval s
    reset_irb and return [] if s.strip == "exit"
    result = open("http://tryruby.hobix.com/irb?cmd=#{CGI.escape(s)}", 
            {'Cookie' => "_session_id=#{$session}"}).read
    result[/^Your session has been closed/] ? (reset_irb and try_eval s) : result.split("\n")
  end
  
  # Look for svn changes.
  def poll
    return unless (Time.now - $last_poll > 15 rescue true)
    $last_poll = Time.now    
    $store.each do |repo, last|
      (Hpricot(`svn log #{repo} -rHEAD:#{last} --limit 10 --xml`)/:logentry).reverse[1..-1].each do |ci|
        $store[repo] = rev = ci.attributes['revision'].to_i
        say "Commit #{rev} to #{repo.split("/").last} by #{(ci/:author).text}: #{(ci/:msg).text}"
      end rescue nil
    end
    File.open(STORE, 'w') {|f| f.puts YAML.dump($store)}
  end
  
  # Post a url to the del.icio.us account.
  def post url
    query = {:url => url,
      :description => (((Hpricot(open(url))/:title).first.innerHTML or url) rescue url),
      :tags => (Hpricot(open("http://del.icio.us/url/check?url=#{CGI.escape(url)}"))/'.alphacloud'/:a).map{|s| s.innerHTML}.join(" "),
      :replace => 'yes' }
    begin
      http = Net::HTTP.new('api.del.icio.us', 443)         
      http.use_ssl = true      
      http.start do |http|
        req = Net::HTTP::Get.new('/v1/posts/add?' + query.map{|k,v| "#{k}=#{CGI.escape(v)}"}.join('&'))
        req.basic_auth DELICIOUS_USER, DELICIOUS_PASS
        http.request(req)
      end.body
    end
  end
  
end


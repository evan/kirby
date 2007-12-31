%w[open3 daemons socket singleton open-uri cgi pathname hpricot yaml net/https].map{|s| require s}

=begin rdoc
In-channel commands:
<tt>'>> CODE'</tt>:: evaluate code in IRB.
<tt>'reset_irb'</tt>:: get a clean IRB session.
<tt>'add_svn [repository_url]'</tt>:: watch an SVN repository.
<tt>'add_atom [atom_feed_url]'</tt>:: watch an atom feed, such as a Git repository
=end

class Kirby

  attr_reader :config  
  
  def initialize(opts = {})

    # Defaults
    path = File.expand_path(".").to_s
    nick = opts[:nick] || config[:nick] || "kirby-dev"

    @config ||= {
      :svns => "#{path}/#{nick}.svns",
      :atoms => "#{path}/#{nick}.atoms",
      :pidfile => "#{path}/#{nick}.pid",
      :nick => nick,
      :channel => 'kirby-dev',
      :server => "irc.freenode.org",
      :delicious_user => nil,
      :delicious_pass => nil,
      :silent => false,
      :log => false,
      :logfile => "#{path}/#{nick}.log",
      :time_format => '%Y/%m/%d %H:%M:%S',
      :debug => false
    }
    
    # Nicely merge current options
    opts.each do |key, value|
      config[key] = value if value
    end
  end
  
  # Connect and reconnect to the server  
  def restart    
    log "Restarting"
    puts config.inspect if config[:debug]
      
    @svns = (YAML.load_file config[:svns] rescue {})
    @atoms  = (YAML.load_file config[:atoms] rescue {})

    @socket.close if @socket
    connect
    listen
  end
  
  # Connect to the IRC server.
  def connect    
    log "Connecting"
    @socket = TCPSocket.new(config[:server], 6667)
    write "USER #{config[:nick]} #{config[:nick]} #{config[:nick]} :#{config[:nick]}"
    write "NICK #{config[:nick]}"
    write "JOIN ##{config[:channel]}"
  end
  
  # The event loop. Waits for socket traffic, and then responds to it. The server sends <tt>PING</tt> every 3 minutes, which means we don't need a separate thread to check for svn updates. All we do is wake on ping (or channel talking).
  def listen
    @socket.each do |line|
      puts "GOT: #{line.inspect}" if config[:debug]
      poll if !config[:silent]
      case line.strip
        when /^PING/
          write line.sub("PING", "PONG")[0..-3]
        when /^ERROR/, /KICK ##{config[:channel]} #{config[:nick]} / 
          restart unless line =~ /PRIVMSG/
        when /:(.+?)!.* PRIVMSG ##{config[:channel]} \:\001ACTION (.+)\001/
          log "* #{$1} #{$2}"
        when /:(.+?)!.* PRIVMSG ##{config[:channel]} \:(.+)/
          nick, msg = $1, $2          
          log "<#{nick}> #{msg}"
          if !config[:silent]
            case msg
              when /^>>\s*(.+)/ then try $1.chop
              when /^#{config[:nick]}:/ 
                ["Usage:",  "  '>> CODE': evaluate code in IRB", "  'reset_irb': get a clean IRB session", "  'add_svn [repository_url]': watch an SVN repository", "  'add_atom [atom_feed_url]': watch an atom feed, such as a Git repository"].each {|s| say s}
              when /^reset_irb/ then reset_irb
              when /^add_svn (.+?)(\s|\r|\n|$)/ then @svns[$1] = 0 and say @svns.inspect
              when /^add_atom (.+?)(\s|\r|\n|$)/ then @atoms[$1] = '' and say @atoms.inspect
              when /(http:\/\/.*?)(\s|\r|\n|$)/ then post($1) if config[:delicious_pass] 
            end
          end
      end
    end
  end
  
  # Send a raw string to the server.
  def write s
    raise RuntimeError, "No socket" unless @socket
    @socket.puts s += "\r\n"
    puts "WROTE: #{s.inspect}" if config[:debug]
  end
  
  # Write a string to the log, if the logfile is open.
  def log s
    # Open log, if necessary
    if config[:log]
      puts "LOG: #{s}" if config[:debug]
      File.open(config[:logfile], 'a') do |f|
        f.puts "#{Time.now.strftime(config[:time_format])} #{s}"
      end
    end
  end
  
  # Eval a piece of code in the <tt>irb</tt> environment.
  def try s
    reset_irb unless @session
    try_eval(s).select{|e| e !~ /^\s+from .+\:\d+(\:|$)/}.each {|e| say e} rescue say "session error"
  end
  
  # Say something in the channel.
  def say s
    write "PRIVMSG ##{config[:channel]} :#{s[0..450]}"
    log "<#{config[:nick]}> #{s}"
    sleep 1
  end
    
  # Get a new <tt>irb</tt> session.
  def reset_irb
    say "Began new irb session"
    @session = try_eval("!INIT!IRB!")
  end
  
  # Inner loop of the try method.
  def try_eval s
    reset_irb and return [] if s.strip == "exit"
    result = open("http://tryruby.hobix.com/irb?cmd=#{CGI.escape(s)}", 
            {'Cookie' => "_session_id=#{@session}"}).read
    result[/^Your session has been closed/] ? (reset_irb and try_eval s) : result.split("\n")
  end
  
  # Look for SVN changes. Note that Rubyforge polls much better if you use the http:// protocol instead of the svn:// protocol for your repository.
  def poll
    return unless (Time.now - $last_poll > 15 rescue true)
    $last_poll = Time.now    
    @svns.each do |repo, last|
      (Hpricot(`svn log #{repo} -rHEAD:#{last} --limit 10 --xml`)/:logentry).reverse[1..-1].each do |ci|
        @svns[repo] = rev = ci.attributes['revision'].to_i
        say "Commit #{rev} to #{repo.split("/").last} by #{(ci/:author).text}: #{(ci/:msg).text}"
      end rescue nil
    end
    File.open(config[:svns], 'w') {|f| f.puts YAML.dump(@svns)}
    
    @atoms.each do |feed, last|
      begin
        e = (Hpricot(open(feed))/:entry).first
        @atoms[feed] = link = e.at("link")['href']
        say "#{(e/:title).text} by #{((e/:author)/:name).text} : #{link}" unless link == last
      rescue
      end
    end
    File.open(config[:atoms], 'w') {|f| f.puts YAML.dump(@atoms)}
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
        req.basic_auth config[:delicious_user], config[:delicious_pass]
        http.request(req)
      end.body
    end
  end
  
end


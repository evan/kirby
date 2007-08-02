#!/usr/bin/env ruby

# An IRC eval bot for Ruby, by Evan Weaver
# http://blog.evanweaver.com/articles/2007/01/02/a-ruby-eval-bot-for-irc-kirby
# Copyright 2007 Cloudburst, LLC. See included LICENSE file.
# Version 3

# * * * * * /path/to/kirby.rb [-d|-no-d] nick channel server delicious_username delicious_password --silent 2>&1 > /dev/null

%w[rubygems open3 daemons socket singleton open-uri cgi pathname hpricot yaml net/https].map{|s| require s}

NICK = (ARGV[1] or "kirby-dev")
CHANNEL = ("#" + (ARGV[2] or "kirby-dev"))
SERVER = (ARGV[3] or "irc.freenode.org")
DELICIOUS_USER, DELICIOUS_PASS = ARGV[4], ARGV[5]
SILENT = ARGV[6] == "--silent"
UML_EVAL = ARGV[7] == "--uml"

class Kirby
  include Singleton
    
  def restart
    $store = (YAML.load_file STORE rescue {})
    @socket.close if @socket
    connect
    listen
  end
  
  def connect
    @socket = TCPSocket.new(SERVER, 6667)
    write "USER #{[NICK]*3*" "} :#{NICK}"
    write "NICK #{NICK}"
    write "JOIN #{CHANNEL}"
  end
  
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
              when /^#{NICK}/ then say "Usage: '>> CODE'. Say 'reset_irb' for a clean session."
              when /^reset_irb/ then reset_irb
              when /^add_svn (.+?)(\s|\r|\n|$)/ then $store[$1] = 0 and say $store.inspect
            end unless SILENT
            post($1) if DELICIOUS_PASS and msg =~ /(http:\/\/.*?)(\s|\r|\n|$)/ 
          end
      end
    end
  end
  
  def write s
    raise RuntimeError, "No socket" unless @socket
    @socket.puts s += "\r\n"
#    puts "WROTE: #{s.inspect}"
  end
  
  def try s
    reset_irb unless $session
    try_eval(s).select{|e| e !~ /^\s+from .+\:\d+(\:|$)/}.each {|e| say e} rescue say "session error"
  end
  
  def say s
    write "PRIVMSG #{CHANNEL} :#{s[0..450]}"
    sleep 1
  end
    
  def reset_irb
    say "Began new irb session"
    if UML_EVAL
      $session.map{|io| io.close} if $session
      $session = Open3.popen3("/usr/local/bin/irb -f -r rubygems --noprompt --noreadline --back-trace-limit 1 2>&1")[0..1]
    else
      $session = try_eval("!INIT!IRB!")
    end
  end
  
  def try_eval s
    reset_irb and return [] if s.strip == "exit"
    if UML_EVAL
      $session.first.puts s
      result = []
      result << $session.last.readline while select([$session.last],nil,nil,1)
      (result[-1] = "=> " + result[-1]) if result[-1] && result[-1] !~ /^\s+from/ # ugh
      result[1..-1]
    else
      result = open("http://tryruby.hobix.com/irb?cmd=#{CGI.escape(s)}", 
              {'Cookie' => "_session_id=#{$session}"}).read
      result[/^Your session has been closed/] ? (reset_irb and try_eval s) : result.split("\n")
    end
  end
  
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

PATH = Pathname.new(__FILE__).dirname.realpath.to_s
STORE = PATH + '/kirby.repositories'
PIDFILE = PATH + '/kirby.pid'
pid = open(PIDFILE).gets.chomp rescue nil

if !pid or `ps #{pid}`.split("\n").size < 2
  puts "Starting"
  Daemons.daemonize if ARGV[0] == '-d'  #:ontop => true
  open(PIDFILE, 'w') {|f| f.puts $$}
  Kirby.instance.restart
end


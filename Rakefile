
require 'rubygems'
require 'echoe'

Echoe.new("kirby", `cat CHANGELOG`[/^v([\d\.]+)\. /, 1]) do |p|  
  p.name = "kirby"
  p.rubyforge_name = "fauna"
  p.description = p.summary = "A super-clean IRC bot with sandboxed Ruby evaluation, svn watching, and link-logging to del.icio.us."
  p.url = "http://github.com/evan/kirby/"
  p.docs_host = "evan.github.com/fauna/"
  p.changes = `cat CHANGELOG`[/^v([\d\.]+\. .*)/, 1]

  p.extra_deps = ["hpricot", "daemons"]  
  p.rdoc_pattern = /bin|lib|README|CHANGELOG|LICENSE/    
  p.require_signed = true
end

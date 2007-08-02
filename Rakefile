
require 'rubygems'
require 'echoe'

Echoe.new("kirby", `cat CHANGELOG`[/^v([\d\.]+)\. /, 1]) do |p|
  
  p.name = "kirby"
  p.rubyforge_name = "fauna"
  p.description = p.summary = "A super-clean IRC bot with sandboxed Ruby evaluation, svn watching, and link-logging to del.icio.us."
  p.url = "http://blog.evanweaver.com/pages/code#kirby"
  p.changes = `cat CHANGELOG`[/^v([\d\.]+\. .*)/, 1]
  
  p.need_tar = false
  p.need_tar_gz = true  
  
  p.rdoc_pattern = /bin|README|CHANGELOG|LICENSE/
    
end

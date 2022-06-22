#!/usr/bin/ruby
# encoding: utf-8
#
# (C) 2022 Mattias Schlenker for tribe29 GmbH

require 'webrick'
require 'fileutils'
require 'optparse'
require 'nokogiri'
require 'json'
require 'rexml/document'
require 'net/http'
require 'net/https'

# require 'rexml/document'
# require 'asciidoctor'

# Configuration either from cmdline arguments or from cfg file
$basepath = nil # Path to the checkmk-docs directory
$templates = nil # Path to the checkmkdocs-styling directory
$cachedir = nil # Path to the cache directory, needed for the menu 
$port = 8088 # Port to use
$cfgfile = nil
$injectcss = nil
$injectjs = nil
$checklinks = 1

# Cache files here
$cachedfiles = Hash.new
# Cache links, only check once per session, empty string means everything is OK
$cachedlinks = Hash.new
# FIXME later: Currently we are limited to one branch
$branches = "localdev"
$latest = "localdev"
$onthispage = {
	"de" => "Auf dieser Seite",
	"en" => "On this page"
}
$menuage = {
	"de" => nil,
	"en" => nil
}
$menufrags = {
	"de" => nil,
	"en" => nil
}
$mimetypes = {
	"html" => "text/html",
	"css" => "text/css",
	"js" => "text/javascript",
	"woff" => "font/woff",
	"woff2" => "font/woff2",
	"eot" => "application/vnd.ms-fontobject",
	"png" => "image/png",
	"jpg" => "image/jpeg",
	"jpeg" => "image/jpeg",
	"svg" => "image/svg+xml"
}

$allowed = [] # Store a complete list of all request paths
$html = [] # Store a list of all HTML files

def create_config
	opts = OptionParser.new
	opts.on('-s', '--styling', :REQUIRED) { |i| $templates = i }
	opts.on('-d', '--docs', :REQUIRED) { |i| $basepath = i }
	opts.on('-c', '--cache', :REQUIRED) { |i| $cachedir = i }
	opts.on('-p', '--port', :REQUIRED) { |i| $port = i }
	opts.on('--config', :REQUIRED) { |i| $cfgfile = i }
	opts.on('--inject-css', :REQUIRED) { |i| $injectcss = i }
	opts.on('--inject-js', :REQUIRED) { |i| $injectjs = i }
	opts.on('--check-links', :REQUIRED) { |i| $checklinks = i.to_i}
	opts.parse!
	# Try to find a config file
	# 1. command line 
	# 2. home directory .config/checkmk-docserve.cfg
	# 3. program directory
	if $cfgfile.nil? 
		[ __dir__ + "/checkmk-docserve.cfg", Dir.home + "/.config/checkmk-docserve.cfg" ].each { |f|
			$cfgfile = f if File.exists? f
		}
	end
	unless $cfgfile.nil?
		jcfg = JSON.parse(File.read($cfgfile))
		$templates = jcfg["styling"] unless jcfg["styling"].nil?
		$basepath = jcfg["docs"] unless jcfg["docs"].nil?
		$port = jcfg["port"] unless jcfg["port"].nil?
		$cachedir = jcfg["cache"] unless jcfg["cache"].nil?
		$injectcss = jcfg["inject-css"] unless jcfg["inject-css"].nil?
		$injectjs = jcfg["inject-js"] unless jcfg["inject-js"].nil?
		$checklinks = jcfg["check-links"] unless jcfg["check-links"].nil?
		$stderr.puts jcfg
	end
	[ $templates, $basepath, $cachedir ].each { |o|
		if o.nil?
			puts "At least specify: --styling <dir> --docs <dir> --cache <dir>"
			exit 1
		end
	}
end

# Create a list of all allowed files:
def create_filelist
	$allowed = []
	# Allow all asciidoc files except includes and menus
	$onthispage.each { |lang, s| 
		Dir.entries($basepath + "/" + lang).each { |f|
			if f =~ /\.asciidoc/ 
				fname = "/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
				unless f =~ /^(include|menu)/
					$allowed.push fname
					$html.push fname
				end
			end
		}
	}
	# Allow all images, but change their paths to include the language
	Dir.entries($basepath + "/images").each { |f|
		if f =~ /\.(png|jpeg|jpg|svg)$/
			$allowed.push "/latest/images/" + f
		end
	}
	# Allow all icons
	Dir.entries($basepath + "/images/icons").each { |f|
		if f =~ /\.(png|jpeg|jpg|svg)$/
			$allowed.push "/latest/images/icons/" + f
		end
	}
	# Allow all files in any subdirectory in assets
	Dir.entries($templates + "/assets").each { |d|
		if File.directory?($templates + "/assets/" + d)
			unless d =~ /^\./
				Dir.entries($templates + "/assets/" + d).each { |f|
					$allowed.push "/assets/" + d + "/" + f if File.file?($templates + "/assets/" + d + "/" + f)
				}
			end
		end
	}
	# Allow the lunr index
	$onthispage.each { |lang, s| 
		$allowed.push "/latest/lunr.index.#{lang}.js"
	}
	$allowed.push "/latest/index.html"
	$allowed.push "/latest/"
	$allowed.push "/latest"
	$allowed.each { |f| $stderr.puts f }
end


def prepare_cache
	[ "de", "en" ].each { |l|
		FileUtils.mkdir_p($cachedir + "/" + $latest + "/" + l )
	}
	[ "js", "css" ].each { |l|
		FileUtils.mkdir_p($cachedir + "/assets/" + l )
	}
end

# Do initial caching of the menu:
def prepare_menu
	[ "de", "en" ].each { |lang|
		path = "/#{lang}/menu.asciidoc"
		s = SingleDocFile.new path
		$cachedfiles[path] = s
	}
end

# Store a single file: 
#  - name of source file
#  - revision of source file
#  - precompiled HTML
class SingleDocFile
	@html = nil
	@mtime = nil
	@filename = nil
	@lang = "en"
	@errors = []
	@xmlerrs = [] # Store the trace from REXML
	@blocked = false # Make sure no concurrent asciidoctor processes are running
	
	# Initialize, first read
	def initialize(filename)
		@filename = filename
		reread
	end
	
	# Check whether the page can be parsed as XML (HTML5 must be validating as XML)
	def check_xml
		return if @filename =~ /menu\.asciidoc$/
		@xmlerrs = []
		doc = nil
		begin 
			doc = REXML::Document.new(@html)
		rescue => e
			@xmlerrs = caller
		end
	end
	
	# Check all links and internal references
	def check_links(doc)
		broken_links = Hash.new
		return broken_links if $checklinks < 1
		doc.css("a").each { |a|
			$stderr.puts a unless a["href"].nil?
			href = a["href"].split("#")[0]
			if $cachedlinks.has_key? href
				broken_links[href] = $cachedlinks[href] unless $cachedlinks[href] == ""
			elsif href =~ /^\./ || href =~ /^\// || href == "" || href =~ /^[0-9a-z._-]*$/ || href =~ /checkmk-docs\/edit\/localdev\// || href =~ /tribe29\.com\// || href =~ /checkmk\.com\// || href =~ /^mailto/
				$cachedlinks[href] = ""
			else
				begin
					headers = nil
					url = URI(href)
					resp = Net::HTTP.get_response(url)
					$stderr.puts resp
					$cachedlinks[href] = ""
					if resp.code.to_i > 400 && resp.code.to_i < 500
						$cachedlinks[href] = resp.code
						$cachedlinks[href] = "404 – File not found" if resp.code == "404"
						$cachedlinks[href] = "401 – Unauthorized" if resp.code == "401"
						broken_links[href] = $cachedlinks[href]
					end
				rescue EOFError
					$cachedlinks[href] = "Could not parse response header"
					broken_links[href] = $cachedlinks[href]
				rescue SocketError
					$cachedlinks[href] = "Host not found or port unavailable"
					broken_links[href] = $cachedlinks[href]
				rescue Errno::ECONNRESET
					$cachedlinks[href] = "Connection reset by peer"
					broken_links[href] = $cachedlinks[href]
				end
			end
		}
		return broken_links
	end
	
	# Read an existing file from the cache directory or rebuild if necessary
	def reread
		# Block concurrent builds
		@blocked = true
		@errors = []
		# rebuild_menu
		@mtime = File.mtime($basepath + @filename)
		outfile = "#{$cachedir}/#{$latest}/#{@filename}".gsub(/asciidoc$/, "html")
		@lang = @filename[1..2]
		outdir = "#{$cachedir}/#{$latest}/#{@lang}"
		cached_mtime = 0
		cached_exists = false
		if File.exists?(outfile) && @html.nil?
			cached_mtime = File.mtime(outfile).to_i
			$stderr.puts "Modification time of file on disk: #{cached_mtime}"
			$stderr.puts "Modification time of asciidoc:    #{@mtime.to_i}"
			cached_exists = true if cached_mtime > @mtime.to_i && cached_mtime > $menuage[@lang].to_i
			$stderr.puts "Using file on disk..." if cached_mtime > @mtime.to_i
		end
		cached_exists = false if @filename =~ /menu\.asciidoc$/
		unless cached_exists
			$stderr.puts "Rebuilding file: " + @filename  
			onthispage = $onthispage[@lang]
			comm = ""
			if @filename =~ /menu\.asciidoc$/
				comm = "asciidoctor -T \"#{$templates}/templates/index\" -E slim \"#{$basepath}/#{@lang}/menu.asciidoc\" -D \"#{$cachedir}/#{$latest}/#{@lang}\""
				$stderr.puts comm
			else
				comm = "asciidoctor -a toc-title=\"#{onthispage}\" -a latest=#{$latest} -a branches=#{$branches} -a branch=#{$latest} -a lang=#{@lang} -a jsdir=../../assets/js -a download_link=https://checkmk.com/download -a linkcss=true -a stylesheet=checkmk.css -a stylesdir=../../assets/css -T \"#{$templates}/templates/slim\" -E slim -a toc=right \"#{$basepath}/#{@filename}\" -D \"#{outdir}\""
				$stderr.puts comm
			end
			IO.popen(comm + " 2>&1") { |o|
				while o.gets
					line = $_.strip
					@errors.push line unless line =~ /checkmk\.css/
				end
			}
		end
		@html = File.read(outfile)
		check_xml
		@blocked = false
	end
	
	# Decide whether to reread or just dump the cached file
	def to_html
		$stderr.puts "Checking file: " + $basepath + @filename
		$stderr.puts "Modification time of asciidoc:             " + File.mtime($basepath + @filename).to_s
		$stderr.puts "Modification time of file in memory cache: " + @mtime.to_s
		refresh = false
		refresh = true if File.mtime($basepath + @filename) > @mtime
		# Rebuild asciidoc if necessary
		if refresh == true && @blocked == false
			reread
		end
		# Inject the menu, this will recursively also rebuild if necessary
		html = @html
		unless @filename =~ /menu\.asciidoc$/
			hdoc = Nokogiri::HTML.parse html
			head  = hdoc.at_css "head"
			cnode = hdoc.css("div[id='preamble']")[0]
			# $stderr.puts cnode # .children[0] # .first_element_child
			#@errors.each { |e|
			#	# head.first_element_child.before("<!-- #{e} -->\n")
			#	head.prepend_child "<!-- #{e} -->\n"
			#	#cnode.children[1].before("<div id='adocerrors'>" + @errors.join("<br />") +  "</div>")
			#}
			#@xmlerrs.each { |e|
			#	head.prepend_child "<!-- #{e} -->\n"
			#	cnode.first_element_child.before("<div id='xmlerrors'>" + e.join("<br />") +  "</div>")
			#}
			# cnode.prepend_child("<div id='xmlerrors'>" + @xmlerrs.join("<br />") +  "</div>")
			head.add_child("<style>\n" + File.read(__dir__ + "/docserve.css") + "\n</style>\n")
			unless $injectcss.nil?
				head.add_child("<style>\n" + File.read($injectcss) + "\n</style>\n") if File.file? $injectcss
			end
			broken_links = check_links hdoc
			if @errors.size > 0 || broken_links.size > 0
				enode = "<div id='docserveerrors'>"
				enode += "<h3>Asciidoctor errors</h3><p class='errmono'>" + @errors.join("<br />") +  "</p>" if @errors.size > 0
				if broken_links.size > 0
					enode += "<h3>Broken links</h3><ul>"
					broken_links.each { |l,p|
						enode += "<li><a href='#{l}' target='_blank'>#{l}</a> (#{p})</li>\n"
					}
					enode += "</ul>"
				end
				enode += "</div>\n"
				cnode.prepend_child enode
			end
			mcont = hdoc.css("div[class='main-nav__content']")[0]
			mcont.inner_html = $cachedfiles["/" + @lang + "/menu.asciidoc"].to_html
			body  = hdoc.at_css "body"
			unless $injectjs.nil?
				body.add_child("<script>\n" + File.read($injectjs) + "\n</script>\n") if File.file? $injectjs
			end
			html = hdoc.to_s # html(:indent => 4)
		end
		return html
	end
	attr_accessor :mtime
end

class MyServlet < WEBrick::HTTPServlet::AbstractServlet
	def do_GET (request, response)
		html = nil
		path = request.path
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/latest/en/") if path == "/"
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/latest/en/index.html") if path == "/latest/en/" || path == "/latest/en"
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/latest/de/index.html") if path == "/latest/de/" || path == "/latest/de"
		# split the path
		ptoks = path.strip.split("/")		
		status = 200
		ctype = "application/unknown"
		# Re-create the filelist if a file not listed is requested, an image or an asciidoc file might have been added
		create_filelist unless $allowed.include? path.strip
		if $html.include? path.strip
			if $cachedfiles.has_key? path.strip
				$stderr.puts "Trying to serve from memory cache..."
			else
				filename = "/" + ptoks[-2] + "/" + ptoks[-1].sub(/\.html$/, ".asciidoc")
				$stderr.puts "Add file to cache #{filename}"
				s = SingleDocFile.new filename
				$cachedfiles[path] = s
			end
			html = $cachedfiles[path].to_html
			response.status = status
			response.content_type = "text/html"
			response.body = html
		end
		if html.nil? && $allowed.include?(path.strip)
			if ptoks.include?("assets")
				# Serve assets directly from the assets directory, first, since assets may contain images	
				html = File.read $templates + path
				suffix = ptoks[-1].split(".")[1] 
				ctype= $mimetypes[suffix] if $mimetypes.has_key? suffix
			elsif ptoks.include?("images") && ptoks.include?("icons")
				# Search icons only in the images/icons directory
				html = File.read $basepath + "/images/icons/" + ptoks[-1]
				suffix = ptoks[-1].split(".")[1] 
				ctype= $mimetypes[suffix] if $mimetypes.has_key? suffix
			elsif ptoks.include?("images")
				# Search all other images directly in the images directory
				html = File.read $basepath + "/images/" + ptoks[-1]
				suffix = ptoks[-1].split(".")[1] 
				ctype= $mimetypes[suffix] if $mimetypes.has_key? suffix
			end
			response.status = status
			response.content_type = ctype
			response.body = html
		end
		if html.nil?
			response.status = 404
			response.content_type = "text/html"
			response.body = "<html><body>404 File not found!</body></html>"
		end
	end
end
    
server = WEBrick::HTTPServer.new(:Port => 8088)
server.mount "/", MyServlet

trap("INT") {
    server.shutdown
}

create_config
prepare_cache
prepare_menu
server.start

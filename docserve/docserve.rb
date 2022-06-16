#!/usr/bin/ruby
# encoding: utf-8
#
# (C) 2022 Mattias Schlenker for tribe29 GmbH

require 'webrick'
require 'fileutils'
require 'optparse'
require 'nokogiri'

# require 'rexml/document'
# require 'asciidoctor'

$basepath = nil # Path to the checkmk-docs directory
$templates = nil # Path to the checkmkdocs-styling directory
$cachedir = nil # Path to the cache directory, needed for the menu 
$port = 8088 # Port to use
$cachedfiles = Hash.new

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

# Create a list of all allowed files:
def create_filelist
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

def create_config
	opts = OptionParser.new
	opts.on('-s', '--styling', :REQUIRED) { |i| $templates = i }
	opts.on('-d', '--docs', :REQUIRED) { |i| $basepath = i }
	opts.on('-c', '--cache', :REQUIRED) { |i| $cachedir = i }
	opts.parse!
	[ $templates, $basepath, $cachedir ].each { |o|
		if o.nil?
			puts "At least specify: --styling <dir> --docs <dir> --cache <dir>"
			exit 1
		end
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
	@blocked = false # Make sure no concurrent asciidoctor processes are running
	
	# Initialize, first read
	def initialize(filename)
		@filename = filename
		reread
	end
	
	# Read an existing file from the cache directory or rebuild if necessary
	def reread
		# Block concurrent builds
		@blocked = true
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
			if @filename =~ /menu\.asciidoc$/
				comm = "asciidoctor -T \"#{$templates}/templates/index\" -E slim \"#{$basepath}/#{@lang}/menu.asciidoc\" -D \"#{$cachedir}/#{$latest}/#{@lang}\""
				$stderr.puts comm
				system comm
			else
				comm = "asciidoctor -a toc-title=\"#{onthispage}\" -a latest=#{$latest} -a branches=#{$branches} -a branch=#{$latest} -a lang=#{@lang} -a jsdir=../../assets/js -a download_link=https://checkmk.com/download -a linkcss=true -a stylesheet=checkmk.css -a stylesdir=../../assets/css -T \"#{$templates}/templates/slim\" -E slim -a toc=right \"#{$basepath}/#{@filename}\" -D \"#{outdir}\""
				$stderr.puts comm
				system comm
			end
		end
		@html = File.read(outfile)
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
			head.add_child "<!-- Hallo Welt -->"
			mcont = hdoc.css("div[class='main-nav__content']")[0]
			mcont.inner_html = $cachedfiles["/" + @lang + "/menu.asciidoc"].to_html
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
create_filelist
server.start

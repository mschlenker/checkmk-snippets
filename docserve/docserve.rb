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
$cachedfiles = Hash.new

# FIXME: Currently we are limited to one branch
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

# $css = File.read("default.css")

def prepare_cache
	[ "de", "en" ].each { |l|
		FileUtils.mkdir_p($cachedir + "/" + $latest + "/" + l )
	}
	[ "js", "css" ].each { |l|
		FileUtils.mkdir_p($cachedir + "/assets/" + l )
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
	
	# Initialize, first read
	def initialize(filename)
		@filename = filename
		reread
	end
	
	def rebuild_menu
	# Build the menu if necessary
		[ "de", "en" ].each { |l|
			rebuild = true
			unless $menuage[l].nil?
				rebuild = false if File.mtime("#{$basepath}/#{l}/menu.asciidoc") <= $menuage[l]
			end
			if rebuild
				system("asciidoctor -T \"#{$templates}/templates/index\" -E slim \"#{$basepath}/#{l}/menu.asciidoc\" -D \"#{$cachedir}/#{$latest}/#{l}\"")
				$menuage[l] = File.mtime("#{$basepath}/#{l}/menu.asciidoc")
				# This is not nice! Invalidate the whole cache
				$cachedfiles.each { |k, v| v.mtime = Time.at(0) }
				$menufrags[l] = File.read "#{$cachedir}/#{$latest}/#{l}/menu.html"
			end
		}
	end
	
	# Read an existing file from the cache directory or rebuild if necessary
	# FIXME: Put the menu to its own class
	def reread
		rebuild_menu
		@mtime = File.mtime($basepath + @filename)
		outfile = "#{$cachedir}/#{$latest}/#{@filename}".gsub(/asciidoc$/, "html")
		lang = @filename[1..2]
		outdir = "#{$cachedir}/#{$latest}/#{lang}"
		cached_mtime = 0
		cached_exists = false
		if File.exists?(outfile)
			cached_mtime = File.mtime(outfile).to_i
			$stderr.puts "Mtime of cached file: #{cached_mtime}"
			$stderr.puts "Mtime of asciidoc:    #{@mtime.to_i}"
			$stderr.puts "Mtime of menu:        #{$menuage[lang].to_i}"
			cached_exists = true if cached_mtime > @mtime.to_i && cached_mtime > $menuage[lang].to_i
			$stderr.puts "Using file in cache..." if cached_mtime > @mtime.to_i
		end
		unless cached_exists
			lang = @filename[1..2]
			onthispage = $onthispage[lang]
			system("asciidoctor -a toc-title=\"#{onthispage}\" -a latest=#{$latest} -a branches=#{$branches} -a branch=#{$latest} -a lang=#{lang} -a jsdir=../../assets/js -a download_link=https://checkmk.com/download -a linkcss=true -a stylesheet=checkmk.css -a stylesdir=../../assets/css -T \"#{$templates}/templates/slim\" -E slim -a toc=right \"#{$basepath}/#{@filename}\" -D \"#{outdir}\"")
			@html = nil
		end	
		if @html.nil?
			hdoc = Nokogiri::HTML.parse File.new(outfile)
			$stderr.puts hdoc
			head  = hdoc.at_css "head"
			head.add_child "<!-- Hallo Welt -->"
			mcont = hdoc.css("div[class='main-nav__content']")[0]
			mcont.inner_html = $menufrags[lang]
			@html = hdoc.to_s # html(:indent => 4)
		end
		
		# o = Asciidoctor.load_file($basepath + @filename, safe: :unsafe, standalone: true, template_engine: :slim, attributes: $attributes, base_dir: $basepath + "/en", template_dirs: [ $templates + "/templates/slim", $templates + "/templates/index", "/tmp/en"  ] ) # , :docdir => $basepath)
		
		# @html = o.convert safe: :server # (:docdir => $basepath)
		# $stderr.puts "Rebuild cache for #{@filename}"
		# $stderr.puts o.options
	end
	
	
	
	# Decide whether to reread or just dump the cached file
	def to_html
		$stderr.puts "Checking file: " + $basepath + @filename
		$stderr.puts "Modification time of asciidoc:    " + File.mtime($basepath + @filename).to_s
		$stderr.puts "Modification time of cached file: " + @mtime.to_s
		refresh = false
		# Check all files for their mtime:
		[ $basepath + "/de/menu.asciidoc", $basepath + "/en/menu.asciidoc", $basepath + @filename ].each { |f|
			refresh = true if File.mtime(f) > @mtime
		}
		reread if refresh
		return @html
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
		# Remove /latest from the path
		path = path.sub(/^\/latest\//, "/")
		# Look for a cached file and 
		if $cachedfiles.has_key? path
			html = $cachedfiles[path].to_html
			$stderr.puts "Trying to serve from cache..."
		elsif path =~ /html$/
			filename = path.gsub(/html$/, "asciidoc")
			if File.exists?($basepath + filename)
				$stderr.puts "Add file to cache #{filename}"
				s = SingleDocFile.new filename
				$cachedfiles[path] = s
			end
			html = $cachedfiles[path].to_html if $cachedfiles.has_key? path
		end
		if html.nil?
			if path =~ /\/(.*?)\.(css|js|woff|woff2)$/
				# Search CSS or JS or WOFF in the assets directory
				content = ""
				ctype = "text/javascript"
				# FIXME: pygments can be created in the cache directory...
				assetfile = $templates + "/" + $1 + "." + $2
				$stderr.puts "Searching #{assetfile}"
				if File.exists? assetfile
					content = File.read assetfile
				end
				ctype = "text/css" if path =~ /\.css$/
				ctype = "font/woff" if path =~ /\.woff$/
				ctype = "font/woff2" if path =~ /\.woff2$/
				response.status = 200
				response.content_type = ctype
				response.body = content
			elsif path =~ /images\/(.*)$/
				image = $1
				content = ""
				ctype = "image/png"
				# We have images both in the assets directory as well as in the docs:
				[ $basepath + "/images/" + image, $templates + "/assets/images/" + image ].each { |i|
					if File.exists? i
						content = File.read i
					end
				}
				ctype = "image/svg+xml" if path =~ /\.svg$/
				ctype = "image/jpeg" if path =~ /\.jpg$/
				# FIXME: Serving images this way might only OK for local development
				response.status = 200
				response.content_type = ctype
				response.body = content
			else
				response.status = 404
				response.content_type = "text/plain"
				response.body = "Ooopsy!"
			end
		else
			response.status = 200
			response.content_type = "text/html"
			response.body = html
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
# rebuild_menu
server.start

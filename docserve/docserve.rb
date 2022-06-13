#!/usr/bin/ruby
# encoding: utf-8
#
# (C) 2022 Mattias Schlenker for tribe29 GmbH

require 'webrick'
require 'asciidoctor'

$basepath = ARGV[0]

$calls = 0
$cache = Hash.new
$css = File.read("default.css")

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
	
	# Reread a file from disk
	def reread
		@mtime = File.mtime $basepath + @filename
		o = Asciidoctor.convert_file $basepath + @filename
		@html = o.convert
		$stderr.puts "Rebuild cache for #{@filename}"
	end
	
	# Decide whether to reread or just dump the cached file
	def to_html
		if File.mtime($basepath + @filename) > @mtime
			reread
		end
		return @html
	end
	attr_reader :mtime
end

class MyServlet < WEBrick::HTTPServlet::AbstractServlet
	def do_GET (request, response)
		html = nil
		path = request.path
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/en/") if path == "/"
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/en/index.html") if path == "/en/" || path == "/en"
		response.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/de/index.html") if path == "/de/" || path == "/de"
		# Look for a cached file and 
		if $cache.has_key? path
			html = $cache[path].to_html
			$stderr.puts "Trying to serve from cache..."
		else
			filename = path.gsub(/html$/, "asciidoc")
			if File.exists?($basepath + filename)
				$stderr.puts "Add file to cache #{filename}"
				s = SingleDocFile.new filename
				$cache[path] = s
			end
			html = $cache[path].to_html if $cache.has_key? path
		end
		if html.nil?
			if path =~ /asciidoctor\.css/
				response.status = 200
				response.content_type = "text/css"
				response.body = $css
			elsif File.exists?($basepath + path.sub(/^\/(de|en)\//, "/images/")) && path =~ /\.png$/
				# FIXME: Serving images this way might by OK for local development
				response.status = 200
				response.content_type = "image/png"
				response.body = File.read($basepath + path.sub(/^\/(de|en)\//, "/images/"))
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

server.start
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
require 'uri'
require 'json'
begin
	require 'hunspell'
rescue LoadError
	$stderr.puts "Hunspell missing, working without spell checking"
end

# require 'rexml/document'
# require 'asciidoctor'

# Configuration either from cmdline arguments or from cfg file
$basepath = nil # Path to the checkmk-docs directory
$templates = nil # Path to the checkmkdocs-styling directory
$cachedir = nil # Path to the cache directory, needed for the menu 
$port = 8088 # Port to use
$cfgfile = nil
$injectcss = []
$injectjs = []
$checklinks = 1
$spelling = 1
# Pre-build all files (for statistics and faster caching)
$buildall = 0
# Run in batch mode: Build only the documents requested, print out errors and exit accordingly
$batchmode = 0
# Auto detect files to build
$since = nil
# For posting to slack
$slackauth = nil
$channel = nil

$lunr = Hash.new # Try to retrieve the lunr index from docs.dev or docs
# Cache files here
$cachedfiles = Hash.new
# Same for includefiles
$cachedincludes = Hash.new
# Cache links, only check once per session, empty string means everything is OK
$cachedlinks = Hash.new
# Prepare dictionaries
$dictionaries = Hash.new
# Create a list of files to build at boot
$prebuild = Array.new
# For statistics
$files_built = 0
$total_errors = Array.new

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
	"ttf" => "font/ttf",
	"woff" => "font/woff",
	"woff2" => "font/woff2",
	"eot" => "application/vnd.ms-fontobject",
	"png" => "image/png",
	"jpg" => "image/jpeg",
	"jpeg" => "image/jpeg",
	"svg" => "image/svg+xml",
	"ico" => "image/vnd.microsoft.icon",
	"json" => "application/json",
	"csv" => "text/csv"
}
# Links that are internally used, but redirected externaly.
$ignorebroken = [
	"check_plugins_catalog.html"
]

$allowed = [] # Store a complete list of all request paths
$html = [] # Store a list of all HTML files

def create_config
	opts = OptionParser.new
	opts.on('-s', '--styling', :REQUIRED) { |i| $templates = i }
	opts.on('-d', '--docs', :REQUIRED) { |i| $basepath = i }
	opts.on('-c', '--cache', :REQUIRED) { |i| $cachedir = i }
	opts.on('-p', '--port', :REQUIRED) { |i| $port = i }
	opts.on('--config', :REQUIRED) { |i| $cfgfile = i }
	opts.on('--inject-css', :REQUIRED) { |i| $injectcss = i.split(",") }
	opts.on('--inject-js', :REQUIRED) { |i| $injectjs = i.split(",") }
	opts.on('--check-links', :REQUIRED) { |i| $checklinks = i.to_i}
	opts.on('--spelling', :REQUIRED) { |i| $spelling = i.to_i}
	opts.on('--build-all', :REQUIRED) { |i| $buildall = i.to_i}
	opts.on('--batch', :REQUIRED) { |i| $batchmode = i.to_i}
	opts.on('--pre-build', :REQUIRED) { |i| $prebuild = i.split(",")}
	opts.on('--since', :REQUIRED) { |i| $since = i.to_s}
	opts.on('--slack-auth', :REQUIRED) { |i| $slackauth = i.to_s}
	opts.on('--channel', :REQUIRED) { |i| $channel = i.to_s}
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
		$spelling = jcfg["spelling"] unless jcfg["spelling"].nil?
		$buildall = jcfg["build-all"] unless jcfg["build-all"].nil?
		$prebuild = jcfg["pre-build"] unless jcfg["pre-build"].nil?
		$since = jcfg["since"] unless jcfg["since"].nil?
		$stderr.puts jcfg
	end
	[ $templates, $basepath, $cachedir ].each { |o|
		if o.nil?
			puts "At least specify: --styling <dir> --docs <dir> --cache <dir>"
			exit 1
		end
	}
end

def post2slack(state, elines)
	jhash = Hash.new
	jhash["channel"] = $channel
	jhash["blocks"] = Array.new
	if state < 1
		msg = "No errors found in commits since #{$since}. Continue the good work!"
	else
		msg = "Errors found in commits since #{$since}. See details below!"
	end
	jhash["blocks"].push( { "type" => "section", "text" => { "type" => "mrkdwn", "text" => msg }} )
	eblock = "```" + elines.join("\n") + "```"
	jhash["blocks"].push( { "type" => "section", "text" => { "type" => "mrkdwn", "text" => eblock }} ) if state > 0
	j = jhash.to_json
	puts j.to_s
	unless $channel.nil? || $slackauth.nil?
		uri = URI('https://slack.com/api/chat.postMessage')
		Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
			request = Net::HTTP::Post.new(uri)
			request['Content-Type'] = 'application/json'
			request['Authorization'] = 'Bearer ' + $slackauth
			request.body = j
			response = http.request request # Net::HTTPResponse object
			$stderr.puts "response #{response.body}"
		end
	end
end

# Create a list of all allowed files:
def create_filelist
	$allowed = []
	# Allow all asciidoc files except includes and menus
	$onthispage.each { |lang, s| 
		Dir.entries($basepath + "/" + lang).each { |f|
			if f =~ /\.asciidoc/ 
				fname = "/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
				jname = "/last_change/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
				unless f =~ /^(include|menu)/
					$allowed.push fname
					$allowed.push jname
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
	$allowed.push "/favicon.ico"
	$allowed.push "/errors.csv"
	$allowed.push "/errors.html"
	$allowed.push "/wordcount.html"
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

# Check whether the german dictionary contains "Äffin" (female monkey) in the correct character set
def monkey_search(file)
	return false unless File.exists?(file)
	File.open(file).each { |line| 
		begin
			if line =~ /^Äffin/
				$stderr.puts "Found the female monkey!"
				$stderr.puts line
				return true
			end
		rescue
			# Most probably an error with the charset?
			return false
		end
	}
	return false
end

# Prepare spellchecker
def prepare_hunspell
	[ "de", "en" ].each { |l| $dictionaries[l] = Array.new }
	return if $spelling < 1
	# Require a cache directory
	return if $cachedir.nil?
	begin
		d = Hunspell.new('/usr/share/hunspell/en_US.aff', '/usr/share/hunspell/en_US.dic')
		$stderr.puts("hunspell: using /usr/share/hunspell/en_US.dic with /usr/share/hunspell/en_US.aff")
		$dictionaries["en"].push d
		$dictionaries["de"].push d
		unless monkey_search("/usr/share/hunspell/de_DE.dic")
			system("iconv -f ISO-8859-15 -t UTF-8 -o \"#{$cachedir}/de_DE.dic\" /usr/share/hunspell/de_DE.dic")
			monkey_search($cachedir + "/de_DE.dic")
		end
		# Hunspell dictionary has to be converted to UTF-8, better create an own dictionary
		if File.exists?($cachedir + "/de_DE.dic")
			$dictionaries["de"].push Hunspell.new('/usr/share/hunspell/de_DE.aff', $cachedir + "/de_DE.dic")
			$stderr.puts("hunspell: using #{$cachedir}/de_DE.dic with /usr/share/hunspell/de_DE.aff")
		else
			$dictionaries["de"].push Hunspell.new('/usr/share/hunspell/de_DE.aff',  "/usr/share/hunspell/de_DE.dic")
			$stderr.puts("hunspell: using /usr/share/hunspell/de_DE.dic with /usr/share/hunspell/de_DE.aff")
		end
	rescue
		# No sense to continue from here
		return
	end
	begin
		d = Hunspell.new('/usr/share/hunspell/en_US.aff', $basepath + '/testing/hunspell/brandnames.dic')
		$stderr.puts("hunspell: using #{$basepath}/testing/hunspell/brandnames.dic with /usr/share/hunspell/en_US.aff")
		$dictionaries["en"].push d
		$dictionaries["de"].push d
	rescue
		# Do nothing.
	end
	begin
		if File.exists?($basepath + "/testing/hunspell/extra_de.dic")
			$dictionaries["de"].push Hunspell.new('/usr/share/hunspell/de_DE.aff', $basepath + "/testing/hunspell/extra_de.dic") if File.exists?($basepath + "/testing/hunspell/extra_de.dic")
			$stderr.puts("hunspell: using #{$basepath}/testing/hunspell/extra_de.dic with /usr/share/hunspell/de_DE.aff")
		end
		if File.exists?($basepath + "/testing/hunspell/extra_en.dic")
			$dictionaries["en"].push Hunspell.new('/usr/share/hunspell/en_US.aff', $basepath + "/testing/hunspell/extra_en.dic")
			$stderr.puts("hunspell: using #{$basepath}/testing/hunspell/extra_en.dic with /usr/share/hunspell/en_US.aff")
		end
	rescue
		# Do nothing
	end
end

def get_lunr
	[ "de", "en" ].each { |l|
		[ "http://docs.dev.tribe29.com/master/", "https://docs.checkmk.com/master/" ].each { |u|
			if $lunr[l].nil?
				begin
					headers = nil
					url = URI(u + "lunr.index." + l + ".js")
					resp = Net::HTTP.get_response(url)
					$stderr.puts resp
					# $stderr.puts resp.body
					$lunr[l] = resp.body
				rescue
					$stderr.puts "Accessing lunr index via #{u} failed"
				end
			end
		}
	}
end

# Use the git command to identify files modified in a certain time range.
# The string is passed unmodified, so test compatibility with git log --since='' first.
def get_modified_since(tdiff)
	files = Array.new
	commits = Array.new
	pwd = Dir.pwd
	Dir.chdir $basepath
	unless system "git status"
		Dir.chdir pwd
		return nil
	end
	gitout = IO.popen("git log --since='#{tdiff}'").readlines
	gitout.each { |line|
		if line =~ /^commit\s([0-9a-f]{40})/
			commits.push $1
		end
	}
	commits.each { |commit|
		files = files + IO.popen("git diff-tree --no-commit-id --name-only -r '#{commit}'").readlines
	}
	Dir.chdir pwd
	return files.uniq.map { |f| f.strip }
end

class SingleIncludeFile
	@mtime = nil
	@filename = nil
	@lang = "en"
	
	# Initialize, first read
	def initialize(filename)
		$stderr.puts "Adding #{filename} to list of includes…"
		@filename = filename
		check_age
	end
	attr_accessor :mtime
	
	def check_age
		@mtime = File.mtime($basepath + @filename)
		return @mtime
	end
	
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
	@words = Array.new # Raw array of words
	@xmlerrs = [] # Store the trace from REXML
	@blocked = false # Make sure no concurrent asciidoctor processes are running
	@includes = [] # List of all includes in this file
	@missing_includes = [] # Includes that could not be found
	@misspelled = [] # Array of misspelled words
	@errorline = nil # A CSV line containing errors
	@html_errorline = nil
	# Initialize, first read, depth is level of recursion for checking anchors
	def initialize(filename, depth=0)
		@filename = filename
		@misspelled = []
		@broken_links = Hash.new
		@anchors = []
		@depth = depth
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
	
	# Retrieve all (hidden anchors)
	def get_anchors
		# $stderr.puts "Searching hidden anchor span"
		tdoc = Nokogiri::HTML.parse(@html)
		tdoc.search(".//div[@class='main-nav__content']").remove
		tdoc.xpath("//span[@class='hidden-anchor sr-only']").each  { |n|
			# $stderr.puts "Found hidden anchor span: #{n['id'].to_s}"
			@anchors.push n['id'].to_s
		}
		@anchors.uniq!
	end
	
	# Serach for an XML element that uses a ceratin ID. This usually is used as anchor.
	def search_id(name)
		found = false
		tdoc = Nokogiri::HTML.parse(@html)
		tdoc.search(".//div[@class='main-nav__content']").remove
		tdoc.xpath("//*[@id='#{name}']").each  { |n|
			$stderr.puts "Found id with unique name #{name}"
			@anchors.push name
			found = true
		}
		return found if found == true
		tdoc.xpath("//*[@id='heading_#{name}']").each  { |n|
			$stderr.puts "Found id with unique name heading_#{name}"
			@anchors.push name
			found = true
		}
		return found
	end
	
	# Check anchors in linked documents
	def check_local_anchors(path, anchor)
		return true if @depth < 1
		if $cachedfiles.has_key? "/latest/#{@lang}/#{path}"
			$stderr.puts "Trying to serve from memory cache..."
		else
			filename = "/#{@lang}/#{path}".sub(/\.html$/, ".asciidoc")
			$stderr.puts "Add file to cache #{filename}"
			s = SingleDocFile.new(filename, @depth - 1)
			$cachedfiles[path] = s
		end
		return false if $cachedfiles[path].nil?
		html = $cachedfiles[path].to_html
		$stderr.puts "Now find the link in the freshly built file. #{path}"
		return true if $cachedfiles[path].anchors.include? anchor
		return $cachedfiles[path].search_id(anchor)
		return false
	end
	
	# Check all links and internal references
	def check_links(doc)
		tdoc = doc.clone
		tdoc.search(".//div[@class='main-nav__content']").remove
		broken_links = Hash.new
		return broken_links if $checklinks < 1
		tdoc.css("a").each { |a|
			$stderr.puts a unless a["href"].nil?
			anchor = ""
			unless a["href"].nil?
				toks = a["href"].split("#")
				href = toks[0]
				anchor = toks[1] if toks.size > 1
				# $stderr.puts "Found anchor # #{anchor}" if href.size < 1
			else
				href = "."
			end
			if href =~ /^\./ || href =~ /^\// || href == "" || href.nil? || href =~ /checkmk-docs\/edit\/localdev\// || href =~ /tribe29\.com\// || href =~ /checkmk\.com\// || href =~ /^mailto/
				if href == "" && anchor.size > 0 
					# $stderr.puts "Found anchor #{href} # #{anchor}"
					unless @anchors.include?(anchor) || search_id(anchor)
						broken_links["#" + anchor] = "this file, target anchor missing"
					end
				end
			elsif $cachedlinks.has_key? href
				broken_links[href] = $cachedlinks[href] unless $cachedlinks[href] == ""
			elsif href =~ /^[0-9a-z._-]+$/ 
				# Check local links against file list:
				fname = "/latest/" + @lang + "/" + href
				if $ignorebroken.include? href
					$stderr.puts "Ignore #{fname} - this is allowed to be broken."
				elsif $allowed.include? fname
					$stderr.puts "Found link #{fname} in list of allowed files!"
					if anchor.size > 0
						$stderr.puts "Might need to build #{href} # #{anchor}"
						unless check_local_anchors(href, anchor)
							broken_links["/latest/" + @lang + "/" + href + "#" + anchor] = "Target anchor missing"
						end
					end
				else
					$stderr.puts "Missing #{fname} in list of allowed files!"
					# $cachedlinks[fname] = "404 – File not found"
					broken_links["/latest/" + @lang + "/" + href] = "404 – File not found"
				end
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
				rescue ArgumentError
					$cachedlinks[href] = "Could not convert URI"
					broken_links[href] = $cachedlinks[href]
				rescue EOFError
					$cachedlinks[href] = "Could not parse response header"
					broken_links[href] = $cachedlinks[href]
				rescue SocketError
					$cachedlinks[href] = "Host not found or port unavailable"
					broken_links[href] = $cachedlinks[href]
				rescue Errno::ECONNRESET
					$cachedlinks[href] = "Connection reset by peer"
					broken_links[href] = $cachedlinks[href]
				rescue Errno::ECONNREFUSED
					$cachedlinks[href] = "Connection refused"
					broken_links[href] = $cachedlinks[href]
				rescue OpenSSL::SSL::SSLError
					$cachedlinks[href] = "Unspecified SSL error"
					broken_links[href] = $cachedlinks[href]
				rescue URI::InvalidURIError
					$cachedlinks[href] = "Invalid URI error"
					broken_links[href] = $cachedlinks[href]
				rescue Net::OpenTimeout
					$cachedlinks[href] = "Request timeout"
					broken_links[href] = $cachedlinks[href]
				end
			end
		}
		$stderr.puts "Found #{broken_links.size} broken links."
		broken_links.each { |k,v|
			$stderr.puts "#{k}: #{v}"
		}
		return broken_links
	end
	
	# Read the includes ans also read ignorewords
	def read_includes
		@includes = Array.new
		@ignored = Array.new
		@mtime = File.mtime($basepath + @filename)
		File.open($basepath + @filename).each { |line|
			if line =~ /include::(.*?)\[/
				ifile = $1
				ipath = "/" + @lang + "/" + ifile
				if File.file?($basepath + ipath)
					$cachedincludes[ipath] = SingleIncludeFile.new ipath
				else
					$stderr.puts "Include file is missing: #{ipath}"
				end
				@includes.push ipath
			end
			if line =~ /\/\/(\s*?)IGNORE/
				ltoks = line.strip.split
				@ignored = @ignored + ltoks[2..-1]
			end
		}
	end
	
	def check_includes
		latest_include = @mtime
		@missing_includes = Array.new
		@includes.each { |i|
			if File.file?($basepath + i) && $cachedincludes.has_key?(i)
				mtime = $cachedincludes[i].check_age
				latest_include = mtime if mtime > latest_include
			else
				@missing_includes.push i
			end
		}
		if @filename =~ /index\.asciidoc$/
			# XML files mit column layout and featured topics are treated as includes as well
			# TXT files with most recent updated etc. might be manually updated
			Dir.entries($basepath + "/" + @lang).each { |f|
				if f =~ /xml$/ || f =~ /txt$/
					tmpmtime = File.mtime($basepath + "/" + @lang + "/" + f)
					latest_include = tmpmtime if tmpmtime > latest_include
				end
			}
		end
		return latest_include
	end
	
	def check_age
		imtime = check_includes
		fmtime = File.mtime($basepath + @filename)
		return imtime if imtime > fmtime
		return fmtime
	end
	
	def check_spelling
		@misspelled = Array.new
		@words = Array.new
		return if $spelling < 1
		sps = $dictionaries[@lang]
		words = Array.new
		hdoc = Nokogiri::HTML.parse @html
		hdoc.search(".//div[@class='main-nav__content']").remove
		hdoc.search(".//pre[@class='pygments']").remove
		hdoc.search(".//div[@class='listingblock']").remove
		hdoc.search(".//div[@class='dropdown__language']").remove
		hdoc.search(".//code").remove
		hdoc.search(".//script").remove
		content  = hdoc.css("body main")
		content.search("//text()").each { |node|
			$stderr.puts node.to_s
			n = node.to_s
			[ /—/, /=/, /-/, /–/, /\"/, /\'/, /\//, /„/, /“/,
			  /bspw\./, /bzw\./, /z\.B\./, /ggf\./, /bzgl\./, /usw\./,
			  /\./, /\;/, /\!/, /\?/,
			  /,/, /\:/, /-/, /-/, /\(/, /\)/, /…/, /&/, / /, / /,
			  /#/, /’/, /‘/, / ​/ ].each { |r|
				n = n.gsub(r, " ")
			}
			n.strip.split(/\s+/).each { |w|
				@words.push w.strip unless w.strip == ""
			}
		}
		@words.uniq.sort.each { |w|
			checkw = w.strip
			valid = false
			valid = true if @ignored.include? checkw.strip
			sps.each { |sp|
				valid = true if sp.spellcheck(checkw.strip) == true
				valid = true if sp.spellcheck(checkw.strip.downcase) == true
			}
			puts "+#{checkw}+" if valid == false
			@misspelled.push(checkw.strip) if valid == false
		}
	end
	
	# create statistics on each word - 'sehr einfach' and very easy should be considered togehter
	def count_words
		@wordscount = Hash.new
		@maxwords = 0
		lastword = nil
		@words.each { |w| 
			if @wordscount.has_key? w
				@wordscount[w] += 1
			else
				@wordscount[w] = 1
			end
			@maxwords = @wordscount[w] if @maxwords < @wordscount[w]
			if w == lastword
				unless w =~ /^[0-9]+$/ || @filename =~ /glossar.*?asciidoc/
					$stderr.puts "Found duplicate word! #{w} in #{@filename}"
				end
			end
			if ([ "sehr", "ganz", "very"].include?(lastword) && [ "einfach", "easy" ].include?(w))
				n = @wordscount[lastword + " " + w].to_i
				@wordscount[lastword + " " + w] = n + 1 
			end
			lastword = w
		}
		# Bloody inefficient
		html = ""
		@maxwords.downto(1) { |n|
			@wordscount.each { |k,v|
				if v == n
					$stderr.puts "Wordstats: #{k} #{v}"
					html = html + "<tr><td></td><td>#{k}</td><td>#{v}</td></tr>\n"
				end
			}
		}
		return html
	end
	
	def nicify_startpage(hdoc) # expects HTML tree as Nokogiri object
		begin
			# Extract the featured topic overlay
			featured = Nokogiri::HTML.parse(File.read($basepath + "/" + @lang + "/featured_000.xml"))
			overlay = featured.css("div[id='topicopaque']")
			# Extract the new startpage layout
			landing = Nokogiri::HTML.parse(File.read($basepath + "/" + @lang + "/landingpage.xml"))
			header = landing.css("div[id='header']")
			# Extract the column for featured topic
			ftcol = featured.css("div[id='featuredtopic']")[0]
			fttgt = landing.css("div[id='featuredtopic']")[0]
			fttgt.replace(ftcol)
		rescue
			# Nothing modified at this point
			return hdoc
		end
		hdoc.search(".//main[@class='home']//div[@id='header']").remove
		hdoc.search(".//main[@class='home']//div[@id='content']").remove
		main = hdoc.css("main[class='home']")[0]
		main.add_child overlay
		main.add_child header
		# Identify the container in the target 
		content = landing.css("div[id='content']")
		main.add_child content
		# Get autolists
		[ "most_visited", "recently_added", "recently_updated" ].each { |f|
			h, ul, hdoc = get_autolist f, hdoc
			lists = hdoc.css("div[id='autolists']")[0]
			lists.add_child h
			lists.add_child ul
		}
		# h, ul, hdoc = get_most_searched hdoc
		# lists = hdoc.css("div[id='autolists']")[0]
		# lists.add_child h
		# lists.add_child ul
		return hdoc
	end
	
	def get_most_searched(hdoc)
		h = nil
		p = Nokogiri::XML::Node.new "p", hdoc
		p["id"] = "mostsearched"
		File.open($basepath + "/" + @lang + "/most_searched.txt").each { |line|
			if line =~ /^\#/ || line.strip == ""
				# do nothing
			elsif line =~ /^=\s/
				h = Nokogiri::XML::Node.new "h4", hdoc
				h.content = line.strip.sub(/^=\s/, "")
			else
				# li = Nokogiri::XML::Node.new "li", hdoc
				a = Nokogiri::XML::Node.new "a", hdoc
				a.content = line.strip
				a["href"] = "index.html?" + URI.encode_www_form( [ ["find", line.strip], ["origin", "landingpage"], ["fulloverlay", "1"] ] ) 
				a["onclick"] = "openTheSearch(\"#{line.strip}\");return false;";
				# li.add_child a
				p.add_child a
				t = Nokogiri::XML::Text.new " ", hdoc
				p.add_child t
			end
		}
		return h, p, hdoc
	end
	
	# Convert the auto generated file list to HTML list
	def get_autolist(name, hdoc)
		h = nil
		ul = Nokogiri::XML::Node.new "ul", hdoc
		File.open($basepath + "/" + @lang + "/" + name + ".txt").each { |line|
			if line =~ /^\#/ || line.strip == ""
				# do nothing
			elsif line =~ /^=\s/
				h = Nokogiri::XML::Node.new "h4", hdoc
				h.content = line.strip.sub(/^=\s/, "")
			else
				fname = line.strip
				File.open($basepath + "/" + @lang + "/" + fname + ".asciidoc").each { |aline|
					if aline =~ /^=\s/
						li = Nokogiri::XML::Node.new "li", hdoc
						a = Nokogiri::XML::Node.new "a", hdoc
						a.content = aline.strip.sub(/^=\s/, "").gsub("{CMK}", "Checkmk")
						a["href"] = fname + ".html"
						li.add_child a
						ul.add_child li
					end
				}
			end
		}
		return h, ul, hdoc
	end
	
	# Read an existing file from the cache directory or rebuild if necessary
	def reread
		# Block concurrent builds
		@blocked = true
		@errors = []
		# rebuild_menu
		outfile = "#{$cachedir}/#{$latest}/#{@filename}".gsub(/asciidoc$/, "html")
		@lang = @filename[1..2]
		outdir = "#{$cachedir}/#{$latest}/#{@lang}"
		# Check includes
		read_includes
		@mtime = File.mtime($basepath + @filename)
		@mtime = check_includes
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
		check_spelling
		count_words
		check_xml
		get_anchors
		@blocked = false
	end
	
	# Decide whether to reread or just dump the cached file
	def to_html
		$stderr.puts "Checking file: " + $basepath + @filename
		$stderr.puts "Modification time of asciidoc:             " + File.mtime($basepath + @filename).to_s
		$stderr.puts "Modification time of file in memory cache: " + @mtime.to_s
		# $stderr.puts "Modification time of latest include file:  " + check_includes.to_s
		refresh = false
		refresh = true if File.mtime($basepath + @filename) > @mtime
		refresh = true if check_includes  > @mtime
		# Rebuild asciidoc if necessary
		if refresh == true && @blocked == false
			reread
		end
		# Inject the menu, this will recursively also rebuild if necessary
		html = @html
		@errorline = nil
		@html_errorline = nil
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
			$injectcss.each { |c|
				head.add_child("<style>\n" + File.read(c) + "\n</style>\n") if File.file? c
			}
			broken_links = check_links hdoc
			@broken_links = broken_links
			total_errors = @errors.size + broken_links.size + @misspelled.size + @missing_includes.size
			$stderr.puts "Total errors encountered: #{total_errors}"
			if total_errors > 0
				hname = @filename.sub(/asciidoc$/, 'html')
				@errorline = "http://localhost:#{$port}/latest#{hname};"
				@html_errorline = "<tr><td><a href=\"http://localhost:#{$port}/latest#{hname}\" target=\"_blank\">#{hname}</a></td>"
				enode = "<div id='docserveerrors'>"
				enode += "<h3>Asciidoctor errors</h3><p class='errmono'>" + @errors.join("<br />") +  "</p>" if @errors.size > 0
				if broken_links.size > 0
					enode += "<h3>Broken links</h3><ul>"
					broken_links.each { |l,p|
						enode += "<li><a href='#{l}' target='_blank'>#{l}</a> (#{p})</li>\n"
					}
					enode += "</ul>"
					@errorline = @errorline + broken_links.size.to_s  + ";"
					@html_errorline = @html_errorline + "<td>" + broken_links.size.to_s + "</td>"
				else
					@errorline = @errorline + "0;"
					@html_errorline = @html_errorline + "<td>0</td>"
				end
				if @missing_includes.size > 0
					enode += "<h3>Missing include files</h3><ul>"
					@missing_includes.each { |m|
						enode += "<li>#{m}</li>\n"
					}
					enode += "</ul>"
					@errorline = @errorline + @missing_includes.size.to_s  + ";"
					@html_errorline = @html_errorline + "<td>" + @missing_includes.size.to_s + "</td>"
				else
					@errorline = @errorline + "0;"
					@html_errorline = @html_errorline + "<td>0</td>"
				end
				if @misspelled.size > 0
					enode += "<h3>Misspelled or unknown words</h3><p>"
					enode += @misspelled.join(", ")
					enode += "</p>"
					@errorline = @errorline + @misspelled.size.to_s  + ";\n"
					@html_errorline = @html_errorline + "<td>" + @misspelled.size.to_s + "</td></tr>\n"
				else
					@errorline = @errorline + "0;\n"
					@html_errorline = @html_errorline + "<td>0</td></tr>\n"
				end
				enode += "</div>\n"
				if cnode.nil?
					$stderr.puts "Preamble not found!"
					headernode =  hdoc.css("div[id='header']")[0]
					headernode.add_child enode
				else
					cnode.prepend_child enode
				end
			end
			mcont = hdoc.css("div[class='main-nav__content']")[0]
			mcont.inner_html = $cachedfiles["/" + @lang + "/menu.asciidoc"].to_html unless mcont.nil?
			body  = hdoc.at_css "body"
			body.add_child("<script>\n" + 
				File.read(__dir__ + "/autoreload.js").
				sub("CHANGED", @mtime.to_i.to_s).
				sub("JSONURL", "/last_change/latest" + @filename.sub(".asciidoc", ".html")) + 
				"\n</script>\n")
			$injectjs.each { |j|
				body.add_child("<script>\n" + File.read(j) + "\n</script>\n") if File.file? j
			}
			# Kick the hiring banner:
			hdoc.search(".//div[@id='hiring-banner']").remove
			if @filename =~ /index\.asciidoc$/
				# Remove the content of the main node:
				hdoc = nicify_startpage(hdoc)
			end
			html = hdoc.to_s # html(:indent => 4)
		end
		return html
	end
	attr_accessor :mtime, :errorline, :html_errorline, :words, :wordscount, :maxwords, :lang, :filename, :errors, :misspelled, :broken_links, :anchors
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
				s = SingleDocFile.new(filename, 1)
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
			elsif ptoks.include?("favicon.ico")
				html = File.read __dir__ + "/" + ptoks[-1]
				ctype= $mimetypes["ico"]
			elsif ptoks.include?("errors.csv")
				html = "\Filename\";\"Broken links\";\"Missing includes\";\"Spellcheck errors\";\n"
				$cachedfiles.each { |f, o|
					unless o.errorline.nil?
						html = html + o.errorline
					end
				}
				ctype= $mimetypes["csv"]
			elsif ptoks.include?("errors.html")
				html = "<!DOCTYPE html>\n<html><head><title>Rabbithole</title></head><body>\n" +
					"<table><tr><td>Filename</td><td>Broken links</td><td>Missing includes</td>" +
					"<td>Spellcheck errors</td></tr>\n"
				$cachedfiles.each { |f, o|
					unless o.html_errorline.nil?
						html = html + o.html_errorline
					end
				}
				html = html + "</table></body></html>"
				ctype= $mimetypes["html"]
			elsif ptoks.include?("wordcount.html")
				html = "<!DOCTYPE html>\n<html><head> <meta charset=\"UTF-8\"> <title>Wordstats</title></head><body>\n" +
					"<table><tr><td>Filename</td><td>Word</td><td>Count</td></tr>\n"
				$cachedfiles.each { |f, o|
					html = html + "<tr><td>#{f}</td></tr>\n"
					html = html + o.count_words
				}
				html = html + "</table></body></html>"
				ctype= $mimetypes["html"]
			elsif ptoks.include?("lunr.index.en.js") || ptoks.include?("lunr.index.de.js")
				ttoks = ptoks[-1].split(".")
				html = $lunr[ttoks[2]]
				ctype= $mimetypes["js"]
			elsif ptoks.include?("last_change")
				# Assume path like "last_change/en/agent_linux.html"
				html_path = "/latest/" + ptoks[-2] + "/" + ptoks[-1]
				if $cachedfiles.has_key? html_path
					html = "{ \"last-change\" : " + $cachedfiles[html_path].check_age.to_i.to_s + " }"
				else
					html = "{ \"last-change\" : 0 }"
				end
				ctype= $mimetypes["json"]
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
    
create_config
prepare_cache
prepare_menu
prepare_hunspell

# Override files to pre-build if git --since is requested
unless $since.nil?
	$prebuild = get_modified_since($since)
end

# Pre-build files requested
if $buildall > 0 || $prebuild.size > 0
	html2build = []
	html2build = $prebuild.map { |f| '/latest/' + f.sub(/ˆ\//, '').sub(/asciidoc$/, 'html') }
	# puts html2build
	# puts $buildall.to_s
	create_filelist
	stime = Time.new.to_i
	$stderr.puts "requested buildall, #{$html.size} documents to build" if $buildall > 0
	$html.each { |f|
		if html2build.include?(f) || $buildall > 0
			$stderr.puts "---> INFO: pre-building requested, building #{f}"
			filename = f.sub(/html$/, 'asciidoc').sub(/^\/latest/, '')
			s = SingleDocFile.new filename
			$cachedfiles[filename] = s
			html = $cachedfiles[filename].to_html
			$total_errors += $cachedfiles[filename].broken_links.keys
			$total_errors += $cachedfiles[filename].misspelled
			$files_built += 1
		end
	}
	duration = Time.now.to_i - stime
	$stderr.puts "requested buildall, done, building took #{duration}s"
end

# When batch mode is set, exit here
if $batchmode > 0
	errorlines = []
	state = 1
	# Errors are encountered, exit non zero:
	if $total_errors.size > 0
		errorlines.push "+++> ERROR: prebuilding #{$prebuild} requested, but errors found!"
		$cachedfiles.each { |f|
			if f[1].broken_links.keys.size > 0
				errorlines.push "+++> #{f[1].filename}: #{f[1].broken_links.size} broken links found."
			end
			if f[1].misspelled.size > 0
				errorlines.push "+++> #{f[1].filename}: #{f[1].misspelled.size} misspelled words found."
			end
		}
		errorlines.each { |l| puts l }
		state = 1
		post2slack(state, errorlines)
		exit state
	end
	# If building files is requested, but nothing is built...
	if $prebuild.size > 0 && $files_built < 1
		errorlines.push "+++> ERROR: prebuilding #{$prebuild} requested, but nothing was built!"
		errorlines.each { |l| puts l }
		state = 1
		exit state
	end
	errorlines.push "---> INFO: prebuilding #{$prebuild} requested, done without issues!"
	errorlines.each { |l| puts l }
	state = 0
	exit state
end

# Retrieve the lunr index
get_lunr

server = WEBrick::HTTPServer.new(:Port => 8088)
server.mount "/", MyServlet
trap("INT") {
    server.shutdown
}
$stderr.puts "docserve is ready now, have fun!"
server.start

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
$lunr = Hash.new # Try to retrieve the lunr index from docs.dev or docs

# Cache files here
$cachedfiles = Hash.new
# Same for includefiles
$cachedincludes = Hash.new
# Cache links, only check once per session, empty string means everything is OK
$cachedlinks = Hash.new
# Cache the glossary
$cachedglossary = Hash.new
# Prepare dictionaries
$dictionaries = Hash.new

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
	"svg" => "image/svg+xml",
	"ico" => "image/vnd.microsoft.icon",
	"json" => "application/json"
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
	opts.on('--inject-css', :REQUIRED) { |i| $injectcss = i.split(",") }
	opts.on('--inject-js', :REQUIRED) { |i| $injectjs = i.split(",") }
	opts.on('--check-links', :REQUIRED) { |i| $checklinks = i.to_i}
	opts.on('--spelling', :REQUIRED) { |i| $spelling = i.to_i}
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
		$checklinks = jcfg["spelling"] unless jcfg["spelling"].nil?
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
	$allowed.push "/latest/index.html"
	$allowed.push "/latest/"
	$allowed.push "/latest"
	prepare_glossary
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

# Prepare the glossary
def prepare_glossary
	[ "de", "en" ].each { |lang|
		$cachedglossary[lang] = Hash.new
		path = "/#{lang}/glossar.asciidoc"
		s = SingleDocFile.new path
		$cachedfiles[path] = s
		# $stderr.puts s.to_html
		# doc.css("a").each { |a|
		# mcont = hdoc.css("div[class='main-nav__content']")[0]
		doc = Nokogiri::HTML(s.to_html)
		doc.css("div[class='sect3']").each { |e|
			id = e.css("span[class='hidden-anchor sr-only']")[0]["id"]
			$cachedglossary[lang][id] = e.inner_html
			$allowed.push("/glossary/" + lang + "/" + id) 
		}
		
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

def get_glossary(lang, id)
	return $cachedglossary[lang][id].to_s
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
	@xmlerrs = [] # Store the trace from REXML
	@blocked = false # Make sure no concurrent asciidoctor processes are running
	@includes = [] # List of all includes in this file
	@missing_includes = [] # Includes that could not be found
	@misspelled = [] # Array of misspelled words
	
	# Initialize, first read
	def initialize(filename)
		@filename = filename
		@misspelled = []
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
			begin
				href = a["href"].split("#")[0]
			rescue
				href = "."
			end
			if $cachedlinks.has_key? href
				broken_links[href] = $cachedlinks[href] unless $cachedlinks[href] == ""
			elsif href =~ /^\./ || href =~ /^\// || href == "" || href.nil? || href =~ /^[0-9a-z._-]*$/ || href =~ /checkmk-docs\/edit\/localdev\// || href =~ /tribe29\.com\// || href =~ /checkmk\.com\// || href =~ /^mailto/
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
				rescue OpenSSL::SSL::SSLError
					$cachedlinks[href] = "Unspecified SSL error"
					broken_links[href] = $cachedlinks[href]
				rescue URI::InvalidURIError
					$cachedlinks[href] = "Invalid URI error"
					broken_links[href] = $cachedlinks[href]
				end
			end
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
				words.push w.strip unless w.strip == ""
			}
		}
		words.uniq.sort.each { |w|
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
		[ "recently_added", "recently_updated", "most_visited" ].each { |f|
			h, ul, hdoc = get_autolist f, hdoc
			lists = hdoc.css("div[id='autolists']")[0]
			lists.add_child h
			lists.add_child ul
		}
		h, ul, hdoc = get_most_searched hdoc
		lists = hdoc.css("div[id='autolists']")[0]
		lists.add_child h
		lists.add_child ul
		return hdoc
	end
	
	def get_most_searched(hdoc)
		h = nil
		ul = Nokogiri::XML::Node.new "ul", hdoc
		ul["id"] = "mostsearched"
		File.open($basepath + "/" + @lang + "/most_searched.txt").each { |line|
			if line =~ /^\#/ || line.strip == ""
				# do nothing
			elsif line =~ /^=\s/
				h = Nokogiri::XML::Node.new "h4", hdoc
				h.content = line.strip.sub(/^=\s/, "")
			else
				li = Nokogiri::XML::Node.new "li", hdoc
				a = Nokogiri::XML::Node.new "a", hdoc
				a.content = line.strip
				a["href"] = "index.html?" + URI.encode_www_form( [ ["find", line.strip], ["origin", "landingpage"], ["fulloverlay", "1"] ] ) 
				li.add_child a
				ul.add_child li
			end
		}
		return h, ul, hdoc
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
		check_xml
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
			if @errors.size > 0 || broken_links.size > 0 || @misspelled.size > 0
				enode = "<div id='docserveerrors'>"
				enode += "<h3>Asciidoctor errors</h3><p class='errmono'>" + @errors.join("<br />") +  "</p>" if @errors.size > 0
				if broken_links.size > 0
					enode += "<h3>Broken links</h3><ul>"
					broken_links.each { |l,p|
						enode += "<li><a href='#{l}' target='_blank'>#{l}</a> (#{p})</li>\n"
					}
					enode += "</ul>"
				end
				if @missing_includes.size > 0
					enode += "<h3>Missing include files</h3><ul>"
					@missing_includes.each { |m|
						enode += "<li>#{m}</li>\n"
					}
					enode += "</ul>"
				end
				if @misspelled.size > 0
					enode += "<h3>Misspelled or unknown words</h3><p>"
					enode += @misspelled.join(", ")
					enode += "</p>"
				end
				enode += "</div>\n"
				begin 
					cnode.prepend_child enode
				rescue
					$stderr.puts "Preamble not found!"
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
			elsif ptoks.include?("glossary")
				# /glossary/lang/id
				html = get_glossary(ptoks[-2], ptoks[-1])
				ctype= "text/plain"
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
    
server = WEBrick::HTTPServer.new(:Port => 8088)
server.mount "/", MyServlet

trap("INT") {
    server.shutdown
}

create_config
prepare_cache
prepare_menu
prepare_hunspell
get_lunr
# prepare_glossary
server.start

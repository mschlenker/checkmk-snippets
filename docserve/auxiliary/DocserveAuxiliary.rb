#!/usr/bin/ruby
# encoding: utf-8
#
# (C) 2022, 2023 Mattias Schlenker for Checkmk GmbH

require 'fileutils'
require 'optparse'
require 'nokogiri'
require 'json'
require 'net/http'
require 'net/https'
require 'uri'
require 'json'

class DocserveAuxiliary

    def DocserveAuxiliary.get_config
        cfg = {}
        # Configuration either from cmdline arguments or from cfg file
        cfg['basepath'] = nil # Path to the checkmk-docs directory
        cfg['templates'] = nil # Path to the checkmkdocs-styling directory
        cfg['cachedir'] = nil # Path to the cache directory, needed for the menu 
        cfg['port'] = 8088 # Port to use
        cfg['cfgfile'] = nil
        cfg['injectcss'] = []
        cfg['injectjs'] = []
        cfg['checklinks'] = 1
        cfg['spelling'] = 1
        # Pre-build all files (for statistics and faster caching)
        cfg['buildall'] = 0
        # Run in batch mode: Build only the documents requested, print out errors and exit accordingly
        cfg['batchmode'] = 0
        # Auto detect files to build
        cfg['since'] = nil
        # For posting to slack
        cfg['slackauth'] = nil
        cfg['channel'] = nil
        # Some files to log to
        cfg['linklog'] = nil
        # Compare the structure of both languages
        cfg['structure'] = 0
        # Build the SaaS User Guide
        cfg['saas'] = 0
        cfg['newdir'] = nil
        # Create a list of files to build at boot
        cfg['prebuild'] = []
        # Languages to build
        cfg['languages'] = [ 'en', 'de' ]
        # Output directory for batch build
        cfg['outdir'] = nil
        # Branches for batch builds
        cfg['branches'] = nil
        cfg['build_branches'] = nil
        # Default branch
        cfg['default'] = nil
        # Map virtual branches to nonexisting branches:
        cfg['fake_branches'] = {}
        # This should be moved to another object:
        cfg['toctitle'] = {
            "en" => "On this page",
            "de" => "Auf dieser Seite"
        }
        cfg['usedcss'] = [  "css/checkmk.css", "css/pygments-monokai.css" ] 
        cfg['usedjs'] = [
            "js/manifest.js", "js/vendor.js", "js/app.js",
            "js/lunr.js", "js/lunr.stemmer.support.js",
            "js/lunr.de.js", "js/lunr.client.js"
        ]
        cfg['baseurl'] = 'https://docs.checkmk.com/'

        opts = OptionParser.new
        opts.on('-s', '--styling', :REQUIRED) { |i| cfg['templates'] = i }
        opts.on('-d', '--docs', :REQUIRED) { |i| cfg['basepath'] = i }
        opts.on('-c', '--cache', :REQUIRED) { |i| cfg['cachedir'] = i }
        opts.on('-p', '--port', :REQUIRED) { |i| cfg['port'] = i }
        opts.on('--config', :REQUIRED) { |i| cfg['cfgfile'] = i }
        opts.on('--baseurl', :REQUIRED) { |i| cfg['baseurl'] = i }
        opts.on('--inject-css', :REQUIRED) { |i| cfg['injectcss'] = i.split(",") }
        opts.on('--inject-js', :REQUIRED) { |i| cfg['injectjs'] = i.split(",") }
        opts.on('--check-links', :REQUIRED) { |i| cfg['checklinks'] = i.to_i}
        opts.on('--spelling', :REQUIRED) { |i| cfg['spelling'] = i.to_i}
        opts.on('--build-all', :REQUIRED) { |i| cfg['buildall'] = i.to_i}
        opts.on('--batch', :REQUIRED) { |i| cfg['batchmode'] = i.to_i}
        opts.on('--pre-build', :REQUIRED) { |i| cfg['prebuild'] = i.split(",")}
        opts.on('--since', :REQUIRED) { |i| cfg['since'] = i.to_s}
        opts.on('--slack-auth', :REQUIRED) { |i| cfg['slackauth'] = i.to_s}
        opts.on('--channel', :REQUIRED) { |i| cfg['channel'] = i.to_s}
        opts.on('--linklog', :REQUIRED) { |i| cfg['linklog'] = i.to_s}
        opts.on('--structure', :REQUIRED) { |i| cfg['structure'] = i.to_i}
        opts.on('--saas', :REQUIRED) { |i| cfg['saas'] = i.to_i}
        opts.on('--languages', :REQUIRED) { |i| cfg['languages'] = i.split(",")}
        opts.on('--outdir', :REQUIRED) { |i| cfg['outdir'] = i.to_s}
        opts.on('--branches', :REQUIRED) { |i| cfg['branches'] = i.split(",")}
        opts.on('--build-branches', :REQUIRED) { |i| cfg['build_branches'] = i.split(",")}
        opts.on('--virtual-branches', :REQUIRED) { |i|
            pairs = i.split(",")
            pairs.each { |p|
                ptoks = p.split('=')
                cfg['fake_branches'][ptoks[0]] = ptoks[1]
            }
        }
        opts.on('--default', :REQUIRED) { |i| cfg['default'] = i.to_s}
        opts.on('--new-dir-structure', :REQUIRED) { |i| cfg['newdir'] = i.to_i}
        opts.parse!
        
        unless cfg['cfgfile'].nil?
            jcfg = JSON.parse(File.read(cfg['cfgfile']))
            jcfg.each { |k, v|
                cfg[k] = v
            }
        end
        if cfg['newdir'].nil?
            cfg['newdir'] = DocserveAuxiliary.identify_dir_structure(cfg)
        end
        [ 'templates', 'basepath', 'cachedir' ].each { |o|
            if cfg[o].nil?
                puts "At least specify: --styling <dir> --docs <dir> --cache <dir>"
                exit 1
            else
                cfg[o] = File.expand_path(cfg[o])
            end
        }
        cfg['outdir'] = cfg['cachedir'] + '/out' if cfg['outdir'].nil?
        cfg['srcpath'] = cfg['basepath']
        cfg['srcpath'] = cfg['cachedir'] + '/src' if cfg['newdir'] > 0
        cfg['build_branches'] = cfg['branches'] if cfg['build_branches'].nil?
        return cfg
    end
    
    def DocserveAuxiliary.create_file_list(cfg, idx=false)
        all_allowed = []
        html = []
        images = []
        index = {}
        buildfiles = {}
        cfg['languages'].each { |lang| 
            buildfiles[lang] = []
            index[lang] = []
        }
        if cfg['newdir'] < 1
        # Allow all asciidoc files except includes and menus
            cfg['languages'].each { |lang| 
                Dir.entries(cfg['basepath'] + "/" + lang).each { |f|
                    if f =~ /\.asciidoc/ 
                        fname = "/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
                        jname = "/last_change/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
                        unless f =~ /^(include|menu)/
                            all_allowed.push fname
                            all_allowed.push jname
                            html.push fname
                            buildfiles[lang].push f
                            unless f =~ /^draft/
                                index[lang].push f if DocserveAuxiliary.decide_index(cfg['basepath'] + "/" + lang + "/" + f, idx) == true
                            end
                        end
                    end
                }
            }
        else
            subdirs = [ "common", "onprem" ]
            subdirs = [ "common", "saas" ] if $saas > 0
            cfg['languages'].each { |lang|
                subdirs.each { |d|
                    Dir.entries(cfg['basepath'] + "/src/" + d + "/" + lang).each { |f|
                        if f =~ /\.asciidoc/ 
                            fname = "/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
                            jname = "/last_change/latest/" + lang + "/" + f.sub(/\.asciidoc$/, ".html")
                            unless f =~ /^(include|menu)/
                                all_allowed.push fname
                                all_allowed.push jname
                                html.push fname
                                buildfiles[lang].push f
                                unless f =~ /^draft/
                                    index[lang].push f if DocserveAuxiliary.decide_index(cfg['basepath'] + "/" + lang + "/" + f, idx) == true
                                end
                            end
                        end
                    }
                }
            }
        end
        # Allow all images, but change their paths to include the language
        Dir.entries(cfg['basepath'] + "/images").each { |f|
            if f =~ /\.(png|jpeg|jpg|svg)$/
                all_allowed.push "/latest/images/" + f
                images.push "../images/" + f
            end
        }
        # Allow all icons
        Dir.entries(cfg['basepath'] + "/images/icons").each { |f|
            if f =~ /\.(png|jpeg|jpg|svg)$/
                all_allowed.push "/latest/images/icons/" + f
                images.push "../images/icons/" + f
            end
        }
        # Allow all files in any subdirectory in assets
        Dir.entries(cfg['templates'] + "/assets").each { |d|
            if File.directory?(cfg['templates'] + "/assets/" + d)
                unless d =~ /^\./
                    Dir.entries(cfg['templates'] + "/assets/" + d).each { |f|
                        all_allowed.push "/assets/" + d + "/" + f if File.file?(cfg['templates'] + "/assets/" + d + "/" + f)
                    }
                end
            end
        }
        # Allow the lunr index
        cfg['languages'].each { |lang| 
            all_allowed.push "/latest/lunr.index.#{lang}.js"
        }
        all_allowed.push "/favicon.ico"
        all_allowed.push "/favicon.png"
        all_allowed.push "/errors.csv"
        all_allowed.push "/errors.html"
        all_allowed.push "/wordcount.html"
        all_allowed.push "/images.html"
        all_allowed.push "/images.txt"
        all_allowed.push "/links.html"
        all_allowed.push "/latest/index.html"
        all_allowed.push "/latest/"
        all_allowed.push "/latest"
        return {
            'all_allowed' => all_allowed,
            'html' => html,
            'images' => images,
            'buildfiles' => buildfiles,
            'index' => index
        }
    end
    
    def DocserveAuxiliary.decide_index(fpath, idx)
        return false if idx == false
        File.open(fpath).each { |line|
            return false if line =~ /\/\/\s*REDIRECT-PERMANENT/
            return false if line =~ /\/\/\s*NO-LUNR/
        }
        return true
    end
    
    def DocserveAuxiliary.create_softlinks(cfg)
        return if cfg['newdir'] < 1
        subdirs = [ "includes", "common", "onprem" ]
        subdirs = [ "includes", "common", "saas" ] if $saas > 0
        cfg['languages'].each { |lang|
            FileUtils.mkdir_p "#{cfg['cachedir']}/src/#{lang}"
            subdirs.each { |d|
                FileUtils.ln_s(Dir.glob("#{cfg['basepath']}/src/#{d}/#{lang}/*.a*doc"), 
                    "#{cfg['cachedir']}/src/#{lang}", force: true)
                FileUtils.ln_s(Dir.glob("#{cfg['basepath']}/src/#{d}/#{lang}/*.xml"),
                    "#{cfg['cachedir']}/src/#{lang}", force: true)
                FileUtils.ln_s(Dir.glob("#{cfg['basepath']}/src/#{d}/#{lang}/*.txt"),
                    "#{cfg['cachedir']}/src/#{lang}", force: true)
            }
            FileUtils.ln_s(Dir.glob("#{cfg['basepath']}/src/code/*.a*doc"),
                "#{cfg['cachedir']}/src/#{lang}", force: true)
        }
    end
    
    def DocserveAuxiliary.identify_dir_structure(cfg)
        if File.directory? "#{cfg['basepath']}/src/onprem/en"
            return 1
        elsif File.directory? "#{cfg['basepath']}/en"
            return 0
        end
        return nil
    end
    
    def DocserveAuxiliary.prepare_menu(cfg, branch='localdev')
        cfg['languages'].each { |lang|
            FileUtils.mkdir_p "#{cfg['cachedir']}/#{branch}/#{lang}"
            comm = "asciidoctor -T \"#{cfg['templates']}/templates/index\" -E slim \"#{cfg['srcpath']}/#{lang}/menu.asciidoc\" -D \"#{cfg['cachedir']}/#{branch}/#{lang}\""
            system comm
        }
    end
    
    def DocserveAuxiliary.build_full(cfg, branch='localdev', lang='en', files=nil)
        files = DocserveAuxiliary.create_file_list(cfg) if files.nil?
        f = files['buildfiles'][lang].map { |f| "\"#{cfg['srcpath']}/#{lang}/#{f}\"" }
        b = cfg['build_branches'].join(' ')
        allfiles = f.join(' ')
        outdir = "#{cfg['outdir']}/#{branch}"
        outdir = "#{cfg['outdir']}/latest" if cfg['default'] == branch
        FileUtils.mkdir_p "#{outdir}"
        FileUtils.mkdir_p "#{outdir}/images/icons"
        FileUtils.mkdir_p "#{outdir}/#{lang}"
        comm = "asciidoctor -a toc-title=\"#{cfg['toctitle'][lang]}\" -a latest=\"#{cfg['default']}\" -a branches=\"#{b}\" -a branch=#{branch} -a lang=#{lang} -a jsdir=../../assets/js -a download_link=https://checkmk.com/#{lang}/download -a linkcss=true -a stylesheet=checkmk.css -a stylesdir=../../assets/css -T \"#{cfg['templates']}/templates/slim\" -E slim -a toc=right -D \"#{outdir}/#{lang}\" #{allfiles}"
        system comm
    end
    
    def DocserveAuxiliary.build_4_lunr(cfg, branch='localdev', lang='en', files=nil)
        files = DocserveAuxiliary.create_file_list(cfg) if files.nil?
        return if files['index'][lang].size < 1
        f = files['index'][lang].map { |f| "\"#{cfg['srcpath']}/#{lang}/#{f}\"" }
        allfiles = f.join(' ')
        FileUtils.mkdir_p "#{cfg['cachedir']}/lunr/#{branch}/#{lang}"
        comm = "asciidoctor -D \"#{cfg['cachedir']}/lunr/#{branch}/#{lang}\" #{allfiles}"
        system comm
    end
    
    def DocserveAuxiliary.build_lunr_index(cfg, branch='localdev', lang='en')
        outdir = "#{cfg['outdir']}/#{branch}"
        outdir = "#{cfg['outdir']}/latest" if cfg['default'] == branch
        FileUtils.mkdir_p "#{cfg['cachedir']}/lunr/#{branch}/#{lang}"
        comm = "node \"#{cfg['templates']}/lunr/build_index_#{lang}.js\" \"#{cfg['cachedir']}/lunr/#{branch}/#{lang}\" \"#{outdir}/lunr.index.#{lang}.js\""
        system comm
    end
    
    def DocserveAuxiliary.switch_branch(cfg, branch='master', pull=false)
        b = branch
        b = cfg['fake_branches'][branch] if cfg['fake_branches'].has_key?(branch)
        pwd = Dir.pwd
        Dir.chdir cfg['basepath']
        system('git pull') if pull == true
        system("git checkout \"#{b}\"")
        cfg['newdir'] = DocserveAuxiliary.identify_dir_structure(cfg)
        DocserveAuxiliary.create_softlinks(cfg) if cfg['newdir'] > 0
        Dir.chdir pwd
        return cfg
    end
    
    def DocserveAuxiliary.copy_images(cfg, branch='master')
        outdir = "#{cfg['outdir']}/#{branch}"
        outdir = "#{cfg['outdir']}/latest" if cfg['default'] == branch
        [ "/images", "/images/icons" ].each { |d|
            Dir.entries(cfg['basepath'] + d).each { |f|
                if File.file?(cfg['basepath'] + d + "/" + f)
                    unless f =~ /(_orig|_original)\./ || f =~ /\.xcf$/ || f =~ /\.xcf\.gz$/ 
                        FileUtils.cp(cfg['basepath'] + d + "/" + f, outdir + d)
                    end
                end
            }
        }
    end
    
    def DocserveAuxiliary.dedup_images(cfg, branches=nil)
        branches = cfg['build_branches'] if branches.nil?
        branches.push("latest")
        imgsums = {}
        pwd = Dir.pwd
        Dir.chdir cfg['outdir']
        branches.each { |branch|
            IO.popen("sha256deep -rle \"#{branch}/images\"") { |l|
                while l.gets
                    ltoks = $_.strip.split("  ")
                    imgsums[ltoks[0]] = [] unless imgsums.has_key? ltoks[0]
                    imgsums[ltoks[0]].push ltoks[1]
                end
            }
        }
        Dir.chdir pwd
        FileUtils.mkdir_p "#{cfg['outdir']}/common"
        imgsums.each { |k, v|
            if v.size > 1
                puts "Deduplicating: " + v.join(', ')
                FileUtils.cp(cfg['outdir'] + "/" + v[0], cfg['outdir'] + "/common/" + k) unless File.exist?(cfg['outdir'] + "/common/" + k)
                v.each { |i|
                    upd = '../../common/'
                    upd = '../../../common/' if i =~ /images\/icons\//
                    FileUtils.rm(cfg['outdir'] + "/" + i)
                    FileUtils.ln_sf(upd + k, cfg['outdir'] + "/" + i)
                }
            end
        }
    end
    
    def DocserveAuxiliary.copy_assets(cfg)
        FileUtils.mkdir_p "#{cfg['outdir']}/assets/js"
        FileUtils.mkdir_p "#{cfg['outdir']}/assets/css"
        [ 'fonts/', 'images/' ].each { |d|
            comm = "rsync -avHP --inplace \"#{cfg['templates']}/assets/#{d}/\" \"#{cfg['outdir']}/assets/#{d}/\""
            system comm
        }
        cfg['usedcss'].each { |f|
            comm = "rsync -avHP --inplace \"#{cfg['templates']}/assets/#{f}\" \"#{cfg['outdir']}/assets/css/\""
            system comm
        }
        cfg['usedjs'].each { |f|
            comm = "rsync -avHP --inplace \"#{cfg['templates']}/assets/#{f}\" \"#{cfg['outdir']}/assets/js/\""
            system comm
        }
        comm = "rsync -avHP --inplace \"#{cfg['templates']}//main-sitemap.xsl\" \"#{cfg['outdir']}/\""
        system comm
    end
    
    def DocserveAuxiliary.nicify_startpage(cfg, branch='master', lang='en', hdoc=nil)
        return hdoc unless File.exist?(cfg['basepath'] + "/" + lang + "/featured_000.xml")
        return hdoc unless File.exist?(cfg['basepath'] + "/" + lang + "/landingpage.xml")
        writeback = false
        if hdoc.nil?
            writeback = true
            outdir = "#{cfg['outdir']}/#{branch}"
            outdir = "#{cfg['outdir']}/latest" if cfg['default'] == branch
            html = File.read("#{outdir}/#{lang}/index.html")
            hdoc = hdoc = Nokogiri::HTML.parse html
        end
        begin
            # Extract the featured topic overlay
            featured = Nokogiri::HTML.parse(File.read(cfg['basepath'] + "/" + lang + "/featured_000.xml"))
            overlay = featured.css("div[id='topicopaque']")
            # Extract the new startpage layout
            landing = Nokogiri::HTML.parse(File.read(cfg['basepath'] + "/" + lang + "/landingpage.xml"))
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
            h, ul, hdoc = DocserveAuxiliary.get_autolist(cfg, f, hdoc, lang)
            lists = hdoc.css("div[id='autolists']")[0]
            lists.add_child h
            lists.add_child ul
        }
        if writeback == true
            outf = File.new("#{outdir}/#{lang}/index.html", 'w')
            outf.write hdoc.to_s
            outf.close
        end
        return hdoc
    end
    
    def DocserveAuxiliary.get_autolist(cfg, name, hdoc, lang)
        h = nil
        ul = Nokogiri::XML::Node.new "ul", hdoc
        File.open(cfg['basepath'] + "/" + lang + "/" + name + ".txt").each { |line|
            if line =~ /^\#/ || line.strip == ""
                # do nothing
            elsif line =~ /^=\s/
                h = Nokogiri::XML::Node.new "h4", hdoc
                h.content = line.strip.sub(/^=\s/, "")
            else
                fname = line.strip
                File.open(cfg['basepath'] + "/" + lang + "/" + fname + ".asciidoc").each { |aline|
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
    
    def DocserveAuxiliary.generate_sitemap(cfg, branch, files)
        # Only build the sitemap for the default branch
        return unless cfg['default'] == branch
        moddates = {}
        pwd = Dir.pwd
        Dir.chdir cfg['basepath']
        cfg['languages'].each { |lang|
            moddates[lang] = {}
            files['index'][lang].each { |f|
                lastmod = ` /usr/bin/git log -1 --pretty="format:%ci"  "#{lang}/#{f}" ` 
				if lastmod == "" 
					lastmod = Time.new.strftime("%Y-%m-%d")
				end
                puts lastmod
                moddates[lang][f] = lastmod
            }
        }
        Dir.chdir pwd
        DocserveAuxiliary.dump_sitemap(cfg, moddates)
    end
    
    def DocserveAuxiliary.dump_sitemap(cfg, entries)
        outfile = File.new("#{cfg['outdir']}/sitemap.xml", 'w')
        outfile.write "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + 
            "<?xml-stylesheet type=\"text/xsl\" href=\"#{cfg['baseurl']}/main-sitemap.xsl\"?>\n" + 
            "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" "  + 
            "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "  +
            "xmlns:xhtml=\"http://www.w3.org/1999/xhtml\" "  +
            "xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 "  +
            "http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd " +
            "http://www.w3.org/1999/xhtml\">\n"
        cfg['languages'].each { |lang|
            entries[lang].each { |f,t|
                link = cfg['baseurl'] + "latest/" + lang + "/" +f.gsub(".asciidoc", ".html")
                outfile.write "<url>\n<loc>" + link + "</loc>\n"
                cfg['languages'].each { |l|
                    if entries[l].has_key? f
                        link = cfg['baseurl'] + "latest/" + l + "/" +f.gsub(".asciidoc", ".html")
                        outfile.write "<xhtml:link href=\"" + link +"\" hreflang=\"#{l}\" rel=\"alternate\"/>\n"
                    end
                }
                outfile.write "<lastmod>" + t[0..9] + "</lastmod>\n"
                outfile.write "<changefreq>monthly</changefreq>\n<priority>0.7</priority>\n</url>\n"
            }
        }
        outfile.write "</urlset>\n"
        outfile.close
    end
    
    
end

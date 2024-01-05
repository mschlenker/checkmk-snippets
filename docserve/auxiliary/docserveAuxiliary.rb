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

        opts = OptionParser.new
        opts.on('-s', '--styling', :REQUIRED) { |i| cfg['templates'] = i }
        opts.on('-d', '--docs', :REQUIRED) { |i| cfg['basepath'] = i }
        opts.on('-c', '--cache', :REQUIRED) { |i| cfg['cachedir'] = i }
        opts.on('-p', '--port', :REQUIRED) { |i| cfg['port'] = i }
        opts.on('--config', :REQUIRED) { |i| cfg['cfgfile'] = i }
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
        opts.on('--new-dir-structure', :REQUIRED) { |i| cfg['newdir'] = i.to_i}
        opts.parse!
        
        unless cfg['cfgfile'].nil?
            jcfg = JSON.parse(File.read(cfg['cfgfile']))
            jcfg.each { |k, v|
                cfg[k] = v
            }
        end
        [ 'templates', 'basepath', 'cachedir' ].each { |o|
            if cfg[o].nil?
                puts "At least specify: --styling <dir> --docs <dir> --cache <dir>"
                exit 1
            else
                cfg[o] = File.expand_path(cfg[o])
            end
        }
        return cfg
    end
    
    def docserveAuxiliary.create_file_list(cfg, idx=false)
        all_allowed = []
        html = []
        images = []
        index = []
        buildfiles = {}
        cfg['languages'].each { |lang| buildfiles[lang] = [] }
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
                            # unless f =~ /^draft/
                            #    index.push f unless decide_index(
                            # end
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
        $onthispage.each { |lang, s| 
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
            'buildfiles' => buildfiles
        }
    end
    
    def DocserveAuxiliary.decide_index(cfg, fpath, idx)
        return false if idx == false
        
        return false
    end
    
    def DocserveAuxiliary.create_softlinks(cfg)
        return if cfg['newdir'] < 1
        subdirs = [ "includes", "common", "onprem" ]
        subdirs = [ "includes", "common", "saas" ] if $saas > 0
        $onthispage.each { |lang, s| 
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
    
    
    
end

#!/usr/bin/ruby
# encoding: utf-8
#
# (C) 2022, 2023 Mattias Schlenker for Checkmk GmbH

require 'auxiliary/DocserveAuxiliary'

s = Time.now.to_i

cfg = DocserveAuxiliary.get_config
DocserveAuxiliary.copy_assets(cfg)

cfg['build_branches'].each { |b|
    cfg = DocserveAuxiliary.switch_branch(cfg, b)
    files = DocserveAuxiliary.create_file_list(cfg, true)
    DocserveAuxiliary.prepare_menu(cfg)
    ts = []
    cfg['languages'].each { |lang|
        ts.push Thread.new{ DocserveAuxiliary.build_full(cfg, b, lang, files) }
        ts.push Thread.new{ DocserveAuxiliary.build_4_lunr(cfg, b, lang, files) }
    }
    ts.push Thread.new{ DocserveAuxiliary.generate_sitemap(cfg, b, files) }
    ts.push Thread.new{ DocserveAuxiliary.copy_images(cfg, b) }
    ts.each { |t| t.join }
    cfg['languages'].each { |lang|
        ts.push Thread.new{ DocserveAuxiliary.nicify_startpage_lunr(cfg, b, lang) }
        ts.push Thread.new{ DocserveAuxiliary.nicify_startpage(cfg, b, lang) }
    }
    ts.each { |t| t.join }
    ts = []
    cfg['languages'].each { |lang|
        ts.push Thread.new{ DocserveAuxiliary.build_lunr_index(cfg, b, lang) }
    }
    ts.each { |t| t.join }
}
DocserveAuxiliary.dedup_images(cfg)

e = Time.now.to_i
d = e - s
puts "Build took #{d} seconds."

#!/usr/bin/env ruby

require 'nokogiri'

str = File.new("/tmp/docserve.cache/localdev/de/wato_monitoringagents.html").read

docstruc = []

tdoc = Nokogiri::HTML.parse(str)
tdoc.search(".//div[@class='main-nav__content']").remove
tdoc.xpath(".//div[@class='sect1']").each  { |n|
	docstruc.push "h2"
	n.xpath(".//div[@class='sect2']").each  { |m|
		docstruc.push "h3"
		m.xpath(".//div[@class='sect3']").each  { |o|
			docstruc.push "h4"
		}
	}
	n.xpath(".//table").each  { |t|
		docstruc.push "table"
		rows = 0
		t.xpath(".//tr").each  { |r|
			rows += 1
		}
		docstruc.push "#{rows} rows"
	}
	n.xpath(".//div[@class='imageblock']").each  { |t|
		docstruc.push "img"
	}
	n.xpath(".//div[@class='imageblock border']").each  { |t|
		docstruc.push "img"
	}
	n.xpath(".//ul").each  { |t|
		docstruc.push "ul"
		li = 0
		t.xpath(".//li").each  { |r|
			li += 1
		}
		docstruc.push "#{li} items"
	}
	n.xpath(".//ol").each  { |t|
		docstruc.push "ol"
		li = 0
		t.xpath(".//li").each  { |r|
			li += 1
		}
		docstruc.push  "#{li} items"
	}
	# @anchors.push name
	#found = true
}
#tdoc.css("a").each { |a| [@class='sect1']

puts docstruc.join(", ")
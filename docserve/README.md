Application server for asciidoc
====

This might grow to a live doc server for the Checkmk documentation written in Asciidoc. It's main purpose is to make working on the docs easier. A second use case might be making the build/export process easier.

Use at your own risk.

Requires:

* webrick gem
* asciidoctor gem

Usage:

```
cd docserve
sudo gem install webrick # pretending asciidoctor gem is already there
ruby docserve.rb /path/to/my/local/copy/of/checkmk-docs` 
firefox http://localhost:8088/ # ...or...
firefox http://localhost:8088/de/agent_linux.html
```

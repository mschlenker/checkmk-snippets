Application server for asciidoc
====

This might grow to a live doc server for the Checkmk documentation written in Asciidoc. It's main purpose is to make working on the docs easier. A second use case might be making the build/export process easier.

Use at your own risk.

Requires:

* webrick gem
* asciidoctor executable

Usage:

```
cd docserve
sudo gem install webrick # pretending asciidoctor gem is already there
ruby docserve.rb --docs ~/git/checkmk-docs --styling ~/git/checkmkdocs-styling --cache /tmp/doccache
firefox http://localhost:8088/
```

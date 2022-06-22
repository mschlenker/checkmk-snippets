Application server for asciidoc
====

This might grow to a live doc server for the Checkmk documentation written in Asciidoc. It's main purpose is to make working on the docs easier. A second use case might be making the build/export process easier.

Use at your own risk.

Requires:

* webrick gem
* nokogiri gem
* tilt gem
* asciidoctor executable

Usage:

```
cd docserve
sudo gem install webrick # pretending asciidoctor gem is already there
ruby docserve.rb --docs ~/git/checkmk-docs --styling ~/git/checkmkdocs-styling --cache /tmp/doccache
firefox http://localhost:8088/
```

You might use a JSON config file, either searched as `$HOME/.config/checkmk-docserve.cfg` or in the program directory or specified via the CLI option `--config` followed by the path to the configuration file.

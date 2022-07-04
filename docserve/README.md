Application server for asciidoc
====

This might grow to a live doc server for the Checkmk documentation written in Asciidoc. It's main purpose is to make working on the docs easier. A second use case might be making the build/export process easier.

Use at your own risk.

Requires:

* webrick gem
* nokogiri gem
* tilt gem
* slim gem
* concurrent-ruby gem (recommended)
* asciidoctor executable
* asciidoctor-diagram gem
* pygments.rb gem

Due to a bug your checkmkdocs-styling repo need two empty menu files:

```
cd checkmkdocs-styling
for l in de en ; do
    mkdir ${l}
    touch ${l}/menu.html.slim
done
```

Usage:

```
cd docserve
sudo gem install webrick # pretending everything for asciidoctor is already there
ruby docserve.rb --docs ~/git/checkmk-docs --styling ~/git/checkmkdocs-styling --cache /tmp/doccache
firefox http://localhost:8088/
```

You might use a JSON config file, either searched as `$HOME/.config/checkmk-docserve.cfg` or in the program directory or specified via the CLI option `--config` followed by the path to the configuration file.

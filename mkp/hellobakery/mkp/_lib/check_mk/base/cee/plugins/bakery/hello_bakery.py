#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021 Mattias Schlenker <ms@mattiasschlenker.de> for tribe29 GmbH
# License: GNU General Public License v2
#
# Reference for details:
# https://docs.checkmk.com/latest/en/bakery_api.html
#
# This file defines which files (binaries and configuration) will be added
# to a Checkmk agent that is assembled with the agent bakery.

import json
from pathlib import Path
from typing import Iterable, TypedDict, List

# Import a whole lot of the bakery API. This might be too much, but probably will
# help you when extending our example.

from .bakery_api.v1 import (
    OS,
    DebStep,
    RpmStep,
    SolStep,
    Plugin,
    PluginConfig,
    SystemBinary,
    Scriptlet,
    WindowsConfigEntry,
    register,
    FileGenerator,
    ScriptletGenerator,
    WindowsConfigGenerator,
    quote_shell_string,
)

class HelloBakeryConfig(TypedDict, total=False):
   interval: int
   user: str
   content: str

def get_hello_bakery_plugin_files(conf: HelloBakeryConfig) -> FileGenerator:
   # In some cases you may want to override user input here to ensure a minimal
   # interval!
   interval = conf.get('interval')

   # Source file with this name is taken from ~/local/share/check_mk/agents/plugins/
   # It will be installed under this name in /usr/lib/check_mk_agent/plugins/<interval>/
   # or in /usr/lib/check_mk_agent/plugins/ (if synchronous call is requested)
   # on the target system.
   yield Plugin(
      base_os=OS.LINUX,
      source=Path('hello_bakery'),
      target=Path('hello_bakery'),
      interval=interval,
   )
   
   # This example skips an agent plugin for Solaris systems. If unsure whether
   # Python is present, you might want to add a Korn shell script instead:
   #
   #yield Plugin(
   #   base_os=OS.SOLARIS,
   #   source=Path('hello_bakery.solaris.ksh'),
   #   target=Path('hello_bakery'),
   #   interval=interval,
   #)
   
   # Install a CMD file for Windows (BAT/PS/VMS are recommended defaults):
   yield Plugin(
      base_os=OS.WINDOWS,
      source=Path('hello_bakery.cmd'),
      target=Path('hello_bakery.bat'),
      interval=interval,
   )
   
   # Put a configuration file to the list for Linux systems:
   # Switch of the banner, since it uses hash as comment.
   yield PluginConfig(base_os=OS.LINUX,
                     lines=_get_linux_cfg_lines(conf['user'], conf['content']),
                     target=Path('hello_bakery.json'),
                     include_header=False)
   
   # Put a configuration file to the list for Solaris systems:
   # If we build a configuration file that can be sourced as shell snippet, we can
   # keep the banner:
   #
   #yield PluginConfig(base_os=OS.SOLARIS,
   #                  lines=_get_solaris_cfg_lines(conf['user'], conf['content']),
   #                  target=Path('hello_bakery.cfg'),
   #                  include_header=True)

   # In some cases the agent needs to be accompanied by a binary. This dumps
   # the binary mentioned to the default binary directionary (typically /usr/bin)
   # and registers the file with the package manager.
   #
   #for base_os in [OS.LINUX]:
   #   yield SystemBinary(
   #      base_os=base_os,
   #      source=Path('some_binary'),
   #   )


def _get_linux_cfg_lines(user: str, content: str) -> List[str]:
   # Let's assume that our Linux example plugin uses JSON as configuration file format
   config = json.dumps({'user': user, 'content': content})
   return config.split('\n')

def _get_solaris_cfg_lines(user: str, content: str) -> List[str]:
   # To be loaded with 'source' in Solaris shell script
   return [
      f'USER={quote_shell_string(user)}',
      f'CONTENT={quote_shell_string(user)}',
   ]

# Depending on your preference you might wanna use pickle to dump the config
# or write plain CSV... It's all up to you. Just make sure that configuration files
# are always treated as an array of lines.

# And now for the scriptlets. In Debian based distributions and Solaris, postinst/
# prerm etc. are files on their own. In RPM based systems all scriptlets are sections
# in a larger file. Since each agent plugin has it's own few lines and the plugin in
# general also has some to restart the job, everything will be concatenated.

# Here be dragons: DO NOT issue "exit 0" as last line in your postinst/prerm etc. 
# files since the lines of all plugins that are included are concatenated and trailed
# by the package management scripts that belong to the agent itself. Also never modify
# the environment in a way that might break following scripts. If you have to change
# directory, save the current directory as olddir=`pwd` and change back as last line.

def get_hello_bakery_scriptlets(conf: HelloBakeryConfig) -> ScriptletGenerator:
   installed_lines = ['logger -p Checkmk_Agent "Installed hello_bakery"']
   uninstalled_lines = ['logger -p Checkmk_Agent "Uninstalled hello_bakery"']

   yield Scriptlet(step=DebStep.POSTINST, lines=installed_lines)
   yield Scriptlet(step=DebStep.POSTRM, lines=uninstalled_lines)
   yield Scriptlet(step=RpmStep.POST, lines=installed_lines)
   yield Scriptlet(step=RpmStep.POSTUN, lines=uninstalled_lines)
   yield Scriptlet(step=SolStep.POSTINSTALL, lines=installed_lines)
   yield Scriptlet(step=SolStep.POSTREMOVE, lines=uninstalled_lines)

# Just because we can we will also write a Windows configuration. In contrast to
# Unices, Windows configuration is kept in a centralized file, not in
# individual files for each plugin.

def get_hello_bakery_windows_config(conf: HelloBakeryConfig) -> WindowsConfigGenerator:
   yield WindowsConfigEntry(path=["hello_bakery", "user"], content=conf["user"])
   yield WindowsConfigEntry(path=["hello_bakery", "content"], content=conf["content"])

register.bakery_plugin(
   name="hello_bakery",
   files_function=get_hello_bakery_plugin_files,
   scriptlets_function=get_hello_bakery_scriptlets,
   windows_config_function=get_hello_bakery_windows_config,
)


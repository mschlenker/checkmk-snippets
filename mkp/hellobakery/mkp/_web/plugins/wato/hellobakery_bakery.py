#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021 Mattias Schlenker <ms@mattiasschlenker.de> for tribe29 GmbH
# License: GNU General Public License v2
#
# Reference for details:
# https://docs.checkmk.com/latest/en/bakery_api.html#ruleset
#
# This is the Setup GUI for our "Hello bakery!" plugin. It defines the parameters that
# can be defined using the GUI and that will eventually be written to the configuration
# on the host running the agent.

from cmk.gui.i18n import _
from cmk.gui.plugins.wato import (
    HostRulespec,
    rulespec_registry,
)
from cmk.gui.cee.plugins.wato.agent_bakery.rulespecs.utils import RulespecGroupMonitoringAgentsAgentPlugins
from cmk.gui.valuespec import (
    Age,
    Dictionary,
    TextAscii,
)

def _valuespec_hello_bakery():
    return Dictionary(
        title=_("Hello bakery! (Linux, Solaris, Windows)"),
        help=_("This will deploy my example plugin."),
        elements=[
            ("user", TextAscii(
                title=_("User for example plugin"),
                allow_empty=False,
            )),
            ("content", TextAscii(
                title=_("The actual content"),
                allow_empty=False,
            )),
            ("interval",
             Age(
                 title=_("Run asynchronously"),
                 label=_("Interval for collecting data"),
                 default_value=300, # default: 5 minutes
             )),
        ],
        optional_keys=["interval"],
    )

rulespec_registry.register(
    HostRulespec(
        group=RulespecGroupMonitoringAgentsAgentPlugins,
        name="agent_config:hello_bakery",
        valuespec=_valuespec_hello_bakery,
    ))

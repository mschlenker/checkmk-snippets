#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021 Mattias Schlenker <ms@mattiasschlenker.de> for tribe29 GmbH 
# License: GNU General Public License v2
#
# Reference for details:
# https://docs.checkmk.com/latest/en/devel_check_plugins.html
#
# This file contains the configuration defaults for our "Hello world!" example
# plus hooks to display and alter these defaults in the setup GUI.

# Import localization:

from cmk.gui.i18n import _

# Import the data structures the GUI uses to pass defaults:

from cmk.gui.valuespec import (
    Dictionary,
    Tuple,
    Percentage,
)
from cmk.gui.plugins.wato import (
    CheckParameterRulespecWithoutItem,
    rulespec_registry,
    RulespecGroupCheckParametersOperatingSystem,
)

# Create a function that returns a tuple containing default thresholds,
# the title may be an arbitary string, this serves three tasks:
# 1. Define reasonable defaults
# 2. Provide an entry field with proper range and label for the setup
# 3. Create a dictionary passed to the agent based plugin, either using
#    defaults or the overriden values 

def _parameter_valuespec_hellobakery_levels():
    return Dictionary(
        elements=[
            ("levels", Tuple(
                title=_("Levels"),
                elements=[
                    Percentage(
                        title=_("Warning at"),
                        default_value=80.0,
                    ),
                    Percentage(
                        title=_("Critical at"),
                        default_value=90.0,
                    ),
                ],
            )),
        ],
        # required_keys=['levels'],  # There is only one value, so its required
    )

# Create a rulespec to be used in your agent based plugin:
#
# CheckParameterRulespecWithoutItem - skip the item: 
# check_helloworld(params, section):
# If more than one value is to be checked, you probably would use the item

rulespec_registry.register(
    CheckParameterRulespecWithoutItem(
        # as defined in your check in share/check_mk/checks/
        check_group_name = "hello_bakery",
        group = RulespecGroupCheckParametersOperatingSystem,
        match_type = "dict",
        # the function above to issue default parameters
        parameter_valuespec = _parameter_valuespec_hellobakery_levels,
        title=lambda: _("Morning mood for hello world"),
    ))


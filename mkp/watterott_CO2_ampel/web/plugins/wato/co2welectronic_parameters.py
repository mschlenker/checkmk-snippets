#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# © 2022 Mattias Schlenker for tribe29 GmbH
#
# Background: The Watterott CO2 Ampel ("CO2 traffic light") is a networkabale
# sensor board, primarily made for monitoring CO2. It is open hardware and uses
# an open source firmware.
#
# This GUI plugin creates the inputs for setting thresholds. Remember:
#
# 1. Both temperature sensors (if present) use the same thresholds (use 
#    the most precise one if they are running apart)
# 2. For temperature and humidity corridors can be applied, the graphing
#    system however only accepts upper boundaries
# 3. Currently no thresholds for atmospheric pressure and ambient lighting
#    are used

from cmk.gui.valuespec import (
    Dictionary,
    Tuple,
    Percentage,
    Integer,
    Float,
)
from cmk.gui.plugins.wato import (
    CheckParameterRulespecWithoutItem,
    rulespec_registry,
    RulespecGroupCheckParametersApplications,
    RulespecGroupCheckParametersEnvironment,
)

def _parameter_valuespec_co2_levels():
    return Dictionary(
        elements=[
            ("levels", Tuple(
                title=_("CO₂ levels"),
                elements=[
                    Integer(
                        title=_("Warning above"),
                        default_value=1000,
                    ),
                    Integer(
                        title=_("Critical above"),
                        default_value=1200,
                    ),
                ],
            )),
        ],
    )

rulespec_registry.register(
    CheckParameterRulespecWithoutItem(
        # as defined in your check in share/check_mk/checks/
        check_group_name = "watterott_co2ampel_plugin",
        group = RulespecGroupCheckParametersEnvironment,
        match_type = "dict",
        # the function above to issue default parameters
        parameter_valuespec = _parameter_valuespec_co2_levels,
        title=lambda: _("Sensor levels from Watterott CO2 traffic light"),
    ))


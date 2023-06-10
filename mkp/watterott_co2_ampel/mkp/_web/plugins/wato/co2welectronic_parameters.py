#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# © 2022 Mattias Schlenker for tribe29 GmbH
# © 2023 Mattias Schlenker for Checkmk GmbH
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
            ("co2", Tuple(
                title=_("CO2 levels"),
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
            ("temp_upper", Tuple(
                title=_("Temperature upper"),
                elements=[
                    Float(
                        title=_("Warning above"),
                        default_value=23.0,
                    ),
                    Float(
                        title=_("Critical above"),
                        default_value=26.0,
                    ),
                ],
            )),
            ("temp_lower", Tuple(
                title=_("Temperature lower"),
                elements=[
                    Float(
                        title=_("Warning below"),
                        default_value=17.0,
                    ),
                    Float(
                        title=_("Critical below"),
                        default_value=13.0,
                    ),
                ],
            )),
            ("humidity_upper", Tuple(
                title=_("Humidity upper"),
                elements=[
                    Percentage(
                        title=_("Warning above"),
                        default_value=60.0,
                    ),
                    Percentage(
                        title=_("Critical above"),
                        default_value=65.0,
                    ),
                ],
            )),
            ("humidity_lower", Tuple(
                title=_("Humidity lower"),
                elements=[
                    Percentage(
                        title=_("Warning below"),
                        default_value=35.0,
                    ),
                    Percentage(
                        title=_("Critical below"),
                        default_value=30.0,
                    ),
                ],
            ))
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


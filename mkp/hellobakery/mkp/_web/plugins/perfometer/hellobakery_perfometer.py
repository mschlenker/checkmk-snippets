#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021 Mattias Schlenker <ms@mattiasschlenker.de> for tribe29 GmbH
# License: GNU General Public License v2
#
# Reference for details:
# https://docs.checkmk.com/latest/en/devel_check_plugins.html#perfometer
#
# Configuration for a simple perf-o-meter that displays percentage values.

from cmk.gui.plugins.metrics import perfometer_info

# Just create the most simple perf-o-meter displaying only one linear value.
# We use the variable "hellobakerylevel" as reference. Since output ranges from 0
# to 100 we just use the full range.

perfometer_info.append({
    "type": "linear",
    "segments": ["hellobakerylevel"],
    "total": 100.0,
})


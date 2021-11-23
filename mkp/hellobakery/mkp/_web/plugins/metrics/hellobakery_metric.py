#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021 Mattias Schlenker <ms@mattiasschlenker.de> for tribe29 GmbH
# License: GNU General Public License v2
#
# Reference for details:
# https://docs.checkmk.com/latest/en/devel_check_plugins.html#ownmetricdefinitions
#
# Here we define the metrics for the graph.

# Import everything of relevance
from cmk.gui.i18n import _
from cmk.gui.plugins.metrics import metric_info

metric_info["hellobakerylevel"] = {
    # Set a title, use _() to allow translations
    "title": _("Hello bakery! level"),
    # Set the unit: Percentage has clear borders
    "unit": "%",
    # Choose a color that isn't red/yellow/green 
    "color": "15/a",
}


#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from cmk.gui.i18n import _
from cmk.gui.plugins.metrics.utils import graph_info, indexed_color, metric_info

metric_info["co2ppm"] = {
    "title": _("CO₂ level"),
    "unit": "ppm",
    "color": "#60f088",
}

metric_info["pressure"] = {
    "title": _("Air Pressure"),
    "unit": "pa",
    "color": "11/a",
}

metric_info["lighting"] = {
    "title": _("Light"),
    "unit": "%",
    "color": "21/a",
}

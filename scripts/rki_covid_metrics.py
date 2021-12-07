#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Import everything of relevance
from cmk.gui.i18n import _
from cmk.gui.plugins.metrics import metric_info

metric_info["cases7_per_100k"] = {
    "title": _("7 day incidence (county)"),
    "unit": "",
    "color": "15/a",
}
metric_info["cases7_bl_per_100k"] = {
    "title": _("7 day incidence (state)"),
    "unit": "",
    "color": "15/a",
}
metric_info["death7_lk"] = {
    "title": _("7 day deaths (county)"),
    "unit": "",
    "color": "15/a",
}
metric_info["death7_bl"] = {
    "title": _("7 day deaths (state)"),
    "unit": "",
    "color": "15/a",
}
metric_info["death_rate"] = {
    "title": _("Death rate"),
    "unit": "%",
    "color": "15/a",
}

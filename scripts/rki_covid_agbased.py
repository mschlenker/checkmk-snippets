#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from .agent_based_api.v1 import *

def discover_rki_covid(section):
    yield Service()
    
def check_rki_covid(params, section):
    for line in section:
        if line[0] != "state":
            yield Metric(name=line[0], value=float(line[1]))
    yield Result(state=State.OK, summary="Nothing is OK :-/")
    return

register.check_plugin(
    name = "rki_covid19",
    service_name = "RKI COVID19 by county",
    check_function = check_rki_covid,
    discovery_function = discover_rki_covid,
    check_default_parameters = {}
)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# © 2022 Mattias Schlenker for tribe29 GmbH
#
# Background: The Watterott CO2 Ampel ("CO2 traffic light") is a networkabale
# sensor board, primarily made for monitoring CO2. It is open hardware and uses
# an open source firmware.
#
# https://learn.watterott.com/breakouts/co2-ampel/
# 
# The factory firmware includes a simple Checkmk agent via HTTP/REST-API:
#
# http://12.34.56.78/cmk-agent
#
# <<<check_mk>>>
# AgentOS: arduino
# <<<watterott_co2ampel_plugin>>>
# co2 521
# temp 19.3
# humidity 51.8
# lighting 976
# temp2 19.4
# pressure 1022.0
# <<<local:sep(0)>>>
# P "CO2 level (ppm)" co2ppm=521;1000;1200 CO2/ventilation control with Watterott CO2-Ampel, thresholds taken from sensor board.
#
# Since the agent is only available via HTTP, the monitoring has to be configured
# using "individual program call instead of agent access", see
#
# https://docs.checkmk.com/latest/en/datasource_programs.html
#
# The result looks like:
#
# curl http://$_HOSTADDRESS_4$/cmk-agent
#
# The local check creates a service immediately after discovery. However this
# takes thresholds from the EPROM of the boards which makes central administration 
# difficult. This plugin adds discovery for all other sensors. Since different
# versions of the board have differect sensors, individual discovery is needed.
#
# See ASR3.5 and ASR3.6 (Germany) for thresholds on CO2/temperature/humidity in
# working environments. Only CO2 is quite fixed at 1000ppm. If no quick exchange
# of air is possible, lower thresholds from 1000/1200 to 900/1000.

from .agent_based_api.v1 import *
from .agent_based_api.v1.type_defs import CheckResult, DiscoveryResult, StringTable
from .utils.temperature import check_temperature
from .utils.humidity import check_humidity

def parse_co2ampel(string_table: StringTable):
    parsed = {}

    for key, value in string_table:
        try:
            parsed[key] = int(value)
        except ValueError:
            parsed[key] = float(value)

        if key == "pressure":
            parsed[key] *= 100
        if key == "lighting":
            parsed[key] = parsed[key] * 100.0 / 1024.0

    return parsed

register.agent_section(
    name="watterott_co2ampel_plugin",
    parse_function=parse_co2ampel,
)

def discover_co2ampel_temp(section) -> DiscoveryResult:
    for key in section:
        if key.startswith("temp"):
            yield Service(item=key)

def check_co2ampel_temp(item, params, section) -> CheckResult:
    if item in section:
        yield from check_temperature(
            reading = section[item],
            params = params,
            unique_name = item,
            value_store = get_value_store(),
        )

register.check_plugin(
    name="watterott_co2ampel_temp",
    sections=["watterott_co2ampel_plugin"],
    service_name="Temperature %s",
    discovery_function=discover_co2ampel_temp,
    check_function=check_co2ampel_temp,
    check_ruleset_name="temperature",
    check_default_parameters={
        "levels" : (23.0, 26.0),
        "levels_lower" : (17.0, 13.0),
    },
)

def discover_co2ampel_humidity(section) -> DiscoveryResult:
    if "humidity" in section:
        yield Service(item="Humidity")

def check_co2ampel_humidity(item, params, section) -> CheckResult:
    if "humidity" in section:
        yield from check_humidity(section["humidity"], params)

register.check_plugin(
    name="watterott_co2ampel_humidity",
    sections=["watterott_co2ampel_plugin"],
    service_name="%s",
    discovery_function=discover_co2ampel_humidity,
    check_function=check_co2ampel_humidity,
    check_ruleset_name="humidity",
    check_default_parameters={
        "levels" : (60.0, 65.0),
        "levels_lower" : (35.0, 30.0),
    },
)

def discover_co2ampel_co2(section) -> DiscoveryResult:
    if "co2" in section:
        yield Service()

def check_co2ampel_co2(params, section) -> CheckResult:
    if "co2" in section:
        value = section["co2"]
        levels = params["levels"]
        yield Metric(name="co2ppm",
                     value=value,
                     levels=levels)
        if value > levels[1]:
            yield Result(state=State.CRIT,
                         summary=f"CO₂ level is too high at {value}ppm")
        elif value > levels[0]:
            yield Result(state=State.WARN,
                         summary=f"CO₂ level is slightly too high at {value}ppm")
        else:
            yield Result(state=State.OK, summary=f"CO₂ level is acceptable at {value}ppm")

register.check_plugin(
    name="watterott_co2ampel_co2",
    sections=["watterott_co2ampel_plugin"],
    service_name="CO₂ level",
    discovery_function=discover_co2ampel_co2,
    check_function=check_co2ampel_co2,
    check_ruleset_name="watterott_co2ampel_plugin",
    check_default_parameters={
        "levels" : (1000, 1200),
    },
)

def discover_co2ampel_sensors(section) -> DiscoveryResult:
    for key in section:
        if key in ["humidity", "co2"]:
            continue
        if key.startswith("temp"):
            continue
        yield Service(item=key)

def check_co2ampel_sensors(item, section) -> CheckResult:
    if item in section:
        value = section[item]
        yield Metric(name=item,
                     value=value)
        if item == "pressure":
            value = "%0.2fhPa" % (value / 100.0)
        if item == "lighting":
            value = "%0.1f%%" % value
        yield Result(state=State.OK, summary=f"Sensor info: {value}")

register.check_plugin(
    name="watterott_co2ampel_sensors",
    sections=["watterott_co2ampel_plugin"],
    service_name="Sensor %s",
    discovery_function=discover_co2ampel_sensors,
    check_function=check_co2ampel_sensors,
)

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

def discover_co2_level(section):
    for key, _value in section:
        yield Service(item=key)

def check_co2_level(item, params, section):
    for key, value in section:
        # The Sensirion CO2 sensor 
        if key == "co2" and key == item:
            yield Metric(name="co2", value=int(value), boundaries=(0, 10000), levels=params["co2"])
            if int(value) > params["co2"][1]:
                yield Result(state=State.CRIT, summary=f"CO2 level is too high at {value}ppm (threshold from plugin)") 
                return
            elif int(value) > params["co2"][0]:
                yield Result(state=State.WARN, summary=f"CO2 level is slightly too high at {value}ppm (threshold from plugin)")
                return
            yield Result(state=State.OK, summary=f"CO2 level is acceptable at {value}ppm (threshold from plugin)")
        # Temperature senosr on the Sensirion
        elif key == "temp" and key == item:
            yield Metric(name="temp", value=float(value), boundaries=(-20.0, 80.0), levels=params["temp_upper"])
            if float(value) > params["temp_upper"][1]:
                yield Result(state=State.CRIT, summary=f"Temperature is too high at {value}°C (threshold from plugin)")
                return
            elif float(value) > params["temp_upper"][0]:
                yield Result(state=State.WARN, summary=f"Temperature is slightly too high at {value}°C (threshold from plugin)")
                return
            elif float(value) < params["temp_lower"][1]:
                yield Result(state=State.CRIT, summary=f"Temperature is too low at {value}°C (threshold from plugin)")
                return
            elif float(value) < params["temp_lower"][0]:
                yield Result(state=State.WARN, summary=f"Temperature is slightly too low at {value}°C (threshold from plugin)")
                return
            yield Result(state=State.OK, summary=f"Temperature is acceptable at {value}°C (threshold from plugin)")
        # Boards with pressure sensors have a second temperature sensor as part of the pressure sensor
        elif key == "temp2" and key == item:
            yield Metric(name="temp_2", value=float(value), boundaries=(-20.0, 80.0), levels=params["temp_upper"])
            if float(value) > params["temp_upper"][1]:
                yield Result(state=State.CRIT, summary=f"Temperature (sensor 2) is too high at {value}°C (threshold from plugin)")
                return
            elif float(value) > params["temp_upper"][0]:
                yield Result(state=State.WARN, summary=f"Temperature (sensor 2) is slightly too high at {value}°C (threshold from plugin)")
                return
            elif float(value) < params["temp_lower"][1]:
                yield Result(state=State.CRIT, summary=f"Temperature (sensor 2) is too low at {value}°C (threshold from plugin)")
                return
            elif float(value) < params["temp_lower"][0]:
                yield Result(state=State.WARN, summary=f"Temperature (sensor 2) is slightly too low at {value}°C (threshold from plugin)")
                return
            yield Result(state=State.OK, summary=f"Temperature (sensor 2) is acceptable at {value}°C (threshold from plugin)")
        # The humidity sensor
        elif key == "humidity" and key == item:
            yield Metric(name="humidity", value=float(value), levels=params["humidity_upper"])
            if float(value) > params["humidity_upper"][1]:
                yield Result(state=State.CRIT, summary="Humidity is too humid at " + value + "% (threshold from plugin)")
                return
            elif float(value) > params["humidity_upper"][0]:
                yield Result(state=State.WARN, summary="Humidity is slightly too humid at " + value + "% (threshold from plugin)")
                return
            elif float(value) < params["humidity_lower"][1]:
                yield Result(state=State.CRIT, summary="Humidity is too dry at " + value + "% (threshold from plugin)")
                return
            elif float(value) < params["humidity_lower"][0]:
                yield Result(state=State.CRIT, summary="Humidity is slightly too dry at " + value + "% (threshold from plugin)")
                return
            yield Result(state=State.OK, summary="Humidity is acceptable at " + value + "% (threshold from plugin)")
        # For ambient lighting and pressure (if available) we just create services that are always OK
        elif key == item:
            yield Metric(name=key, value=float(value))
            yield Result(state=State.OK, summary="Sensor " + key + " value " + value + " for informational purpose only, always OK")

register.check_plugin(
    name = "watterott_co2ampel_plugin",
    service_name = "CO2 board %s",
    discovery_function = discover_co2_level,
    check_function = check_co2_level,
    check_ruleset_name = "watterott_co2ampel_plugin",
    # Define some thresholds, the CO2 values are taken according German Arbeitsstättenrichtlinie ASR3.6
    # Change temperatures for the respective work environmen, see ASR A3.5 
    check_default_parameters = { 
        "co2" : (1000, 1200),
        "temp_upper" : (23.0, 26.0),
        "temp_lower" : (17.0, 13.0),
        "humidity_upper" : (60.0, 65.0),
        "humidity_lower" : (35.0, 30.0)
     }
)


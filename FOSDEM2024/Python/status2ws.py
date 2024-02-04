#!/usr/bin/python

import time
import json
import serial
import sys
import getopt
import requests
import pprint
import serial

HOST_NAME = "localhost"
SITE_NAME = "cmktest"
API_URL = f"http://{HOST_NAME}/{SITE_NAME}/check_mk/api/1.0"

USERNAME = "cmkadmin"
PASSWORD = "test123"

hexes = {
    "co2_1" : {
        "Check_MK" : 0,
        "CO2 board co2" : 11,
        "CO2 board temp" : 12,
        "CO2 board humidity" : 23,
        "CO2 board lighting" : 6
        
    },
    "co2_2" : {
        "Check_MK" : 1,
        "CO2 board co2" : 10,
        "CO2 board temp" : 13,
        "CO2 board humidity" : 22,
        "CO2 board lighting" : 7
    },
    "co2_3" : {
        "Check_MK" : 2,
        "CO2 board co2" : 9,
        "CO2 board temp" : 14,
        "CO2 board humidity" : 21,
        "CO2 board lighting" : 18
    },
    "co2_4" : {
        "Check_MK" : 3,
        "CO2 board co2" : 8,
        "CO2 board temp" : 15,
        "CO2 board humidity" : 20,
        "CO2 board lighting" : 19
    },
}

ser = serial.Serial("/dev/ttyACM1", 115200)

session = requests.session()
session.headers['Authorization'] = f"Bearer {USERNAME} {PASSWORD}"
session.headers['Accept'] = 'application/json'

while True:
    for k in hexes:
        resp = session.get(
            f"{API_URL}/objects/host/{k}/collections/services",
            params={
                "query": '{"op": "=", "left": "host_name", "right": "' + k + '"}', 
                "columns": ['host_name', 'description', 'state' ],
            },
        )
        print(resp.status_code)
        if resp.status_code == 200:
            # pprint.pprint(resp.json())
            j = resp.json()
            for s in j['value']:
                print(s['extensions']['description'] + " has value " + str(s['extensions']['state']))
                o = (str(hexes[k][s['extensions']['description']]) + " " + str(s['extensions']['state']) + "\r").encode("utf-8")
                # print(o)
                ser.write(o)
    time.sleep(15)

    
    
    
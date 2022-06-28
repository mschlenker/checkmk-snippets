#!/usr/bin/python3

import urllib.request, json 

co2url = "http://10.76.23.147/json"

print('<<<co2ampel>>>')
with urllib.request.urlopen(co2url) as url:
    data = json.loads(url.read().decode())
    print('co2', data['c'])
    print('temp', data['t'])
    print('humidity', data['h'])
    print('lighting', data['l'])

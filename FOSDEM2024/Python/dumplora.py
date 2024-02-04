#!/usr/bin/python

import time
import json
import serial
import sys
import getopt

co2 = 0
temp = 0
humidity = 0
lighting = 0
lastwrite = 0

opts, args = getopt.getopt(sys.argv[1:],"p:o:s:i:h")
for opt, arg in opts:
	if opt == '-s':
		port = arg
	elif opt == '-i':
		interval = int(arg)
	elif opt == '-h':
		print(help)
		sys.exit()

ser = serial.Serial(port, 115200, timeout=3)

while True:
    data = ser.readline()
    j = json.loads("{}")
    try:
        if data.decode('utf-8').strip() and json.loads(data.decode('utf-8').strip()):
            print(data)
            j = json.loads(data.decode('utf-8').strip())
            h = j['n']
            outfile = "/tmp/" + h + ".txt"
            o = open(outfile, "w")
            o.write("<<<check_mk>>>\n")
            o.write("Version: 2.0.0p1\n")
            o.write("AgentOS: arduino\n")
            o.write("Hostname: " + h + "\n")
            o.write("<<<watterott_co2ampel_plugin>>>\n")
            o.write("co2 " + str(j['c']) + "\n")
            o.write("temp " + str(j['t']) + "\n")
            o.write("humidity " + str(j['h']) + "\n")
            o.write("lighting " + str(j['l']) + "\n")
            o.close()
    except:
        print("Ooops, malformed data!")


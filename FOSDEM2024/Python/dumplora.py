#!/usr/bin/python

import time
import json
import serial
import sys
import getopt
from datetime import datetime, date, timezone

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
    j = json.loads("{}")
    data = ser.readline()
    try:
        if data.decode('utf-8').strip() and json.loads(data.decode('utf-8').strip()):
            j = json.loads(data.decode('utf-8').strip())
            print(str(datetime.now()) + " " + str(j))
            h = j['n']
            outfile = "/tmp/" + h + ".json"
            o = open(outfile, "w")
            o.write(json.dumps(j))
            o.write("\n")
            o.close()
    except:
        print("Ooops, malformed data!")


#!/usr/bin/python

import time
import json
import serial
import sys
import getopt

help = """
This program continously writes a Checkmk spool file for a Watterott CO2 traffic
light that is connected to the USB port. The format is the same as for the REST
endpoint on the WiFi enabled devices. You can change those parameters:

-p optionally specify a host to create piggyback output for
-o change path of outpt file (default /var/lib/check_mk_agent/spool/300_co2_ampel.txt)
-s serial port to use (default /dev/ttyACM0)
-i interval between writes (default 20s)
-h this help

See also:
https://learn.watterott.com/breakouts/co2-ampel/
https://exchange.checkmk.com/p/watterott-co2-ampel
https://docs.checkmk.com/latest/en/piggyback.html
"""

outfile = "/var/lib/check_mk_agent/spool/300_co2_ampel.txt"
piggy = ""
port = '/dev/ttyACM0'
interval = 20

co2 = 0
temp = 0
humidity = 0
lighting = 0
lastwrite = 0

opts, args = getopt.getopt(sys.argv[1:],"p:o:s:i:h")
for opt, arg in opts:
	if opt == '-p':
		piggy = arg
	elif opt == '-o':
		outfile = arg
	elif opt == '-s':
		port = arg
	elif opt == '-i':
		interval = int(arg)
	elif opt == '-h':
		print(help)
		sys.exit()

ser = serial.Serial(port, 115200, timeout=3)
newlines = 0

while newlines < 1:
	data = ser.readline()
	if data.decode('utf-8').strip() == "":
		newlines += 1

while True:
	data = ser.readline()
	if data.decode('utf-8').strip() == "" and int(time.time()) > lastwrite + interval:
		o = open(outfile, "w")
		if piggy != "":
			o.write("<<<<" + piggy + ">>>>\n")
		o.write("<<<watterott_co2ampel_plugin>>>\n")
		o.write("co2 " + str(co2) + "\n")
		o.write("temp " + str(temp) + "\n")
		o.write("humidity " + str(humidity) + "\n")
		o.write("lighting " + str(lighting) + "\n")
		if piggy != "":
			o.write("<<<<>>>>\n")
		o.close()
		lastwrite = int(time.time())
	else:
		toks = data.decode('utf-8').strip().split(": ", 1)
		if toks[0] == 'c':
			co2 = int(toks[1])
		elif toks[0] == 't':
			temp = float(toks[1])
		elif toks[0] == 'h':
			humidity = float(toks[1])
		elif toks[0] == 'l':
			lighting = int(toks[1])

#!/usr/bin/python3

import requests
import json
import os.path
import sys

# File to store status info
statfile = "/tmp/RKI_Data_Status.json"
storedts = "" 

# Request the current status file 
staturl = 'https://opendata.arcgis.com/datasets/38e0356be30642868b4c526424102718_0.geojson'
resp = requests.get(staturl)
fromwhen = resp.json()['features'][0]['properties']['Timestamp_txt']

# Parameters of current data set for counties
dataurl = 'https://opendata.arcgis.com/datasets/917fc37a709542548cc3be077a786c17_0.geojson'

# Matching dumpfile
datafile = "/tmp/RKI_Data_County.json"

if os.path.isfile(statfile):
	# print("File exists.")
	compfile = json.load(open(statfile))
	storedts = compfile['features'][0]['properties']['Timestamp_txt']
	# print(compfile['features'][0]['properties']['Timestamp_txt'])

# Anyway, dump the last status
with open(statfile, 'w') as outfile:
	json.dump(resp.json(), outfile)

# Compare the stored timestamp to the last received and retrieve the dataset if not present
if storedts != fromwhen:
	dresp = requests.get(dataurl)
	with open(datafile, 'w') as outfile:
		json.dump(dresp.json(), outfile)

# Read the actual data and display 
coviddata = json.load(open(datafile))

for (k, v) in coviddata.items():
	if k == 'features':
		for (c) in v:
			if len(sys.argv) < 2:
				print(c['properties']['county'])
			elif sys.argv[1] == c['properties']['county']:
				print('<<<check_mk>>>')
				print('Version: 2.0.0')
				print('AgentOS: noOS')
				print('<<<rki_covid19>>>')
				# print('county ' + c['properties']['county'])
				print('cases7_per_100k ' + str(c['properties']['cases7_per_100k']))
				print('state ' + str(c['properties']['BL']))
				print('cases7_bl_per_100k ' + str(c['properties']['cases7_bl_per_100k']))
				print('death7_lk ' + str(c['properties']['death7_lk']))
				print('death7_bl ' + str(c['properties']['death7_bl']))
				print('death_rate ' + str(c['properties']['death_rate']))

#!/usr/bin/ruby
# encoding: utf-8
# license: GPLv2
# author: Mattias Schlenker for tribe29 GmbH

# First parameter: old file
# Second parameter: new file

require 'openssl'

oldfile = ARGV[0]
newfile = ARGV[1]
allfiles = [ oldfile, newfile ]
inside = false
# oldcerts and newcerts
allcerts = [ [], [] ]
# Serial numbers of certs to speed up comparison
serials = [ [], [] ]
raw = ''
infos = []
warnings = []
errors = []
now = Time.now
loglines = []

[ 0, 1].each { |n|
	File.open(allfiles[n]).each { |line|
		inside = true if line.strip == "-----BEGIN CERTIFICATE-----"
		raw = raw + line if inside == true
		if line.strip == "-----END CERTIFICATE-----"
			inside = false
			cert = OpenSSL::X509::Certificate.new raw
			allcerts[n].push cert
			raw = ''
		end
	}
}

[ 0, 1].each { |n|
	allcerts[n].each { |c| serials[n].push c.serial }
}

allcerts[1].each { |c|
	serial = c.serial
	unless serials[0].include? serial
		warnings.push c
		loglines.push "WARN: added certificate missing in old file."
		loglines.push "    #{c.issuer}"
		loglines.push "    serial:  #{serial}"
		loglines.push "    valid from: #{c.not_before}"
		loglines.push "    valid til:  #{c.not_after}"
		# loglines.push "    fingerprint:  #{c.fingerprint}"
	end
}

allcerts[0].each { |c|
	serial = c.serial
	if now > c.not_after
		# Notify on outdated certificates
		infos.push c
		loglines.push "NOTE: outdated certificate found!"
		loglines.push "    #{c.issuer}"
		loglines.push "    serial: #{serial}"
		loglines.push "    valid til:  #{c.not_after}"
		# loglines.push "    fingerprint:  #{c.fingerprint}"
	else
		# Try to find certificate in new certificate store
		unless serials[1].include? serial
			errors.push c
			loglines.push "ERROR: missing certificate, probably revoked!"
			loglines.push "    #{c.issuer}"
			loglines.push "    serial: #{serial}"
			loglines.push "    valid from: #{c.not_before}"
			loglines.push "    valid til:  #{c.not_after}"
			# loglines.push "    fingerprint:  #{c.fingerprint}"
		end
	end
}

loglines.each { |l| puts l } 
if errors.size > 0 
	puts "Overall state: CRIT"
elsif warnings.size > 0
	puts "Overall state: WARN"
else
	puts "Overall state: OK"
end
puts "Errors: #{errors.size}, warnings: #{warnings.size}, notes: #{infos.size}"

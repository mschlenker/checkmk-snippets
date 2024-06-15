# LORA enabled CO2 monitoring at FOSDEM 24 and Checkmk Conference #10

After having experienced trouble with WiFi enabled CO2 sensors in environments where the 2.4GHz band isvery congested, we opted for a different wireless standard this time.
Since simplicity, robustness and ease of setup were the main goals, we opted for LoRa this time.
Readily available CO2 sensor boards in various configurations are available from [Watterott Electronic](https://watterott.com/).
To keep it simple, we skipped the LoRaWAN part and configured for a simple broadcast without ACK.

To display the readings, not only Checkmk was used, but also 3D printed honeycombs that used WS2812 rings to display red, yellow, green.
This involved a script querying the Checkmk REST API and writing to a serial interface.
On the serial interface an ESP32 running Micropython switched colors according to serial data received.

## Components used

### Arduino for the sending CO2 sensor boards

We added a LoRa broadcast to the demo firmware from Watterott.
Since it would not compile without the LoRa library (or rather big changes to the head of the example), we will not file a pull request for now.
The data broadcasted is one JSON string. This is a waste of bandwith when configured for lower data rates, for our setup it was sufficient.
[The Arduino code is available here.](./Arduino/CO2-Ampel/examples/CO2-Ampel/CO2-Ampel.ino)

### Arduino for the receiver boards

To receive, we configured one board to receive packets and just dump every packet to the serial interface.
We initially wanted to build a receiver just out of a microcontroller and a LoRa Transceiver, but eventually perpetuated the setup when one NDIR sensor broke.
[The Arduino code is available here.](./Arduino/LoraReceiverTest/LoraReceiverTest.ino)

### Python to convert received data to Checkmk agent output

A Python script was used to listen on the serial port the LoRa receiver was connected to.
After every line it was checked whether this was a valid JSON object and then converted to Checkmk agent output in the format used for the [Watterott CO2 plugin for Checkmk](https://exchange.checkmk.com/p/watterott-co2-ampel).
To use the data in the monitoring, it was sufficient to read the agent output file using a data source call:

    cat /tmp/$HOSTNAME$.txt

### Python to query the Checkmk REST API



### Micropython on ESP to switch WS2812

## 3D printed hexagons


#include <SPI.h>
#include <LoRa.h>

//---LoRa---
#define LORA_NODENAME      "co2ampel4" //Wird mit den Messwerten übertragen
#define LORA_TX_POWER      17 //Zwischen 2 und 20, Default 17
#define LORA_FREQ          868E6 //868MHz, Europa
#define LORA_INTERVALL     15000 //Millisekunden zwischen zwei Paketen, Duty Cycle beachten!
#define LORA_SPREAD        7 //Spreading factor, beeinflusst Datenrate, 6-12, Default 7
#define LORA_BANDWIDTH     125E3 //Bandwidth in Hz

void setup() {
  
  Serial.begin(9600);
  while (!Serial);
  LoRa.setPins(20, -1);
  LoRa.enableCrc();
  // Serial.println("LoRa Receiver");

  if (!LoRa.begin(868E6)) {
    Serial.println("Starting LoRa failed!");
    while (1);
  }
  LoRa.setSpreadingFactor(LORA_SPREAD);
  LoRa.setTxPower(LORA_TX_POWER);
  LoRa.setSignalBandwidth(LORA_BANDWIDTH);
  LoRa.enableCrc();
}

void loop() {
  // try to parse packet
  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    // received a packet
    // Serial.print("Received packet '");

    // read packet
    while (LoRa.available()) {
      Serial.print((char)LoRa.read());
    }

    // print RSSI of packet
    // Serial.print("' with RSSI ");
    // Serial.println(LoRa.packetRssi());
  }
}

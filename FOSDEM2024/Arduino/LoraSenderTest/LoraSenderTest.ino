#include <SPI.h>
#include <LoRa.h>

int counter = 0;

void setup() {
  // Serial.begin(9600);
  pinMode(20, OUTPUT);
  LoRa.setPins(20, 3);
  // digitalWrite(20, HIGH);
  // while (!Serial);

  // Serial.println("LoRa Sender");

  if (!LoRa.begin(868E6)) {
    // Serial.println("Starting LoRa failed!");
    while (1);
  }
}

void loop() {
  // Serial.print("Sending packet: ");
  // Serial.println(counter);

  // send packet
  LoRa.beginPacket();
  LoRa.print("hello ");
  LoRa.print(counter);
  LoRa.endPacket();
  delay(3000);
  counter++;
}

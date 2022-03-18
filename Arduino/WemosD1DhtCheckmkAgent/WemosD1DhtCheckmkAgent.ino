#include <DHT.h> //DHT Bibliothek laden
#include <ESP8266WiFi.h>
// This file includes the SSID and PSK, two lines are enough:
// #define ESSID "mynetworkname"
// #define WPAPSK "mypresharedkey"
#include "wifi_secrets.h"

#define DHTPIN D4 //Der Sensor wird an PIN 4 angeschlossen    
#define DHTTYPE DHT11    // Es handelt sich um den DHT11 Sensor

// define some offsets - a narrow gap between ESP and DHT means 
// a higher temperature offset is needed! Sensor offsets are 
// typically +/- 2.5°C. 
#define T_OFFSET 4.5 // sensor shows 5.5°C higher than real value
#define H_OFFSET 2.0 // Sensor shows 2.0% higher than real value 

// define some thresholds
#define T_MIN_WARN 17.0
#define T_MIN_CRIT 15.0
#define T_MAX_WARN 24.0
#define T_MAX_CRIT 26.0
#define H_MIN_WARN 38.0
#define H_MIN_CRIT 34.0
#define H_MAX_WARN 62.0
#define H_MAX_CRIT 66.0

// Port des Web Servers auf 80 setzen
WiFiServer server(6556);

DHT dht(DHTPIN, DHTTYPE); //Der Sensor wird ab jetzt mit „dth“ angesprochen

void setup() {
  // put your setup code here, to run once:
  Serial.begin(9600); //Serielle Verbindung starten
  dht.begin(); //DHT11 Sensor starten
  // Mit dem WiFi-Netzwerk verbinden
  Serial.print("Connecting to WiFi");
  WiFi.begin(ESSID, WPAPSK);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  // Lokale IP-Adresse im Seriellen Monitor ausgeben und Server starten
  Serial.println("");
  Serial.println("WiFi connected");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());
  server.begin();
  delay(2000);
}

void loop() {
  // put your main code here, to run repeatedly:
  delay(500); //Zwei Sekunden Vorlaufzeit bis zur Messung (der Sensor ist etwas träge)
  float Luftfeuchtigkeit = dht.readHumidity(); //die Luftfeuchtigkeit auslesen und unter „Luftfeutchtigkeit“ speichern
  float Temperatur = dht.readTemperature();//die Temperatur auslesen und unter „Temperatur“ speichern
  Serial.print("Luftfeuchtigkeit: "); //Im seriellen Monitor den Text und 
  Serial.print(Luftfeuchtigkeit - H_OFFSET); //die Dazugehörigen Werte anzeigen
  Serial.println(" %");
  Serial.print("Temperatur: ");
  Serial.print(Temperatur - T_OFFSET);
  Serial.println(" Grad Celsius");
  WiFiClient client = server.available(); 
  if (client) {
    Serial.println("Client available");
    client.println("<<<check_mk>>>\nAgentOS: arduino");
    client.print("<<<dht_cmk_plugin>>>\ntemp ");
    client.println(Temperatur - T_OFFSET);
    client.print("humidity ");
    client.println(Luftfeuchtigkeit - H_OFFSET);
    client.println("<<<local:sep(0)>>>");
    // Print out humidity
    if ((Luftfeuchtigkeit - H_OFFSET) < H_MIN_CRIT) {
      client.print("2 \"DHT humidity\" humidity=");
      client.print(Luftfeuchtigkeit - H_OFFSET);
      client.println(" Humidity is too dry");
    } else if ((Luftfeuchtigkeit - H_OFFSET) > H_MAX_CRIT) {
      client.print("2 \"DHT humidity\" humidity=");
      client.print(Luftfeuchtigkeit - H_OFFSET);
      client.println(" Humidity is too wet");
    } else if (H_MIN_CRIT <= (Luftfeuchtigkeit - H_OFFSET) && (Luftfeuchtigkeit - H_OFFSET) < H_MIN_WARN) {
      client.print("1 \"DHT humidity\" humidity=");
      client.print(Luftfeuchtigkeit - H_OFFSET);
      client.println(" Humidity is a bit dry");
    } else if (H_MAX_CRIT >= (Luftfeuchtigkeit - H_OFFSET) && (Luftfeuchtigkeit - H_OFFSET) > H_MAX_WARN) {
      client.print("1 \"DHT humidity\" humidity=");
      client.print(Luftfeuchtigkeit - H_OFFSET);
      client.println(" Humidity is a bit wet");
    }  else {
      client.print("0 \"DHT humidity\" humidity=");
      client.print(Luftfeuchtigkeit - H_OFFSET);
      client.println(" Humidity is comfortable");
    }
    // Print out temperature
    if ((Temperatur - T_OFFSET) < T_MIN_CRIT) {
      client.print("2 \"DHT temperature\" temperature=");
      client.print(Temperatur - T_OFFSET);
      client.println(" Temperature  is too low");
    } else if ((Temperatur - T_OFFSET) > T_MAX_CRIT) {
      client.print("2 \"DHT temperature\" temperature=");
      client.print(Temperatur - T_OFFSET);
      client.println(" Temperature is too high");
    } else if (T_MIN_CRIT <= (Temperatur - T_OFFSET) && (Temperatur - T_OFFSET) < T_MIN_WARN) {
      client.print("1 \"DHT temperature\" temperature=");
      client.print(Temperatur - T_OFFSET);
      client.println(" Temperature is a bit low");
    } else if (T_MAX_CRIT >= (Temperatur - T_OFFSET) && (Temperatur - T_OFFSET) > T_MAX_WARN) {
      client.print("1 \"DHT temperature\" temperature=");
      client.print(Temperatur - T_OFFSET);
      client.println(" Temperature is a bit high");
    } else { 
      client.print("0 \"DHT temperature\" temperature=");
      client.print(Temperatur - T_OFFSET);
      client.println(" Temperature is comfortable");
    }
    // Die Verbindung beenden
    client.stop();
    Serial.println("Client disconnected");
    Serial.println("");
  }
}

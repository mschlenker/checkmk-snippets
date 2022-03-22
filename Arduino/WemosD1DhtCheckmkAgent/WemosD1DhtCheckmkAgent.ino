#include <DHT.h> // Load the DHT11/22 library
#include <ESP8266WiFi.h> // Load ESP WiFi library

// (C) 2022 Mattias Schlenker for tribe29 GmbH
// Due to the libraries used, this code is licensed unter GPL V2

// Agent output as follows, there is one section for a plugin (that yet has to be written)
// and two local checks for which the state is calculated from eight thresholds defined in
// constants below (CRIT/WARN, HI/LOW, temperature/humidity).
/*
<<<check_mk>>>
AgentOS: arduino
<<<dht_cmk_plugin>>>
temp 21.60
humidity 36.40
<<<local:sep(0)>>>
1 "DHT humidity" humidity=36.40 Humidity is a bit dry
0 "DHT temperature" temperature=21.60 Temperature is comfortable
*/

// The file wifi_secrets.h in the same directory as this file contains the SSID and PSK, two
// lines are enough. If you are not using version control you might just use these lines:
// #define ESSID "mynetworkname"
// #define WPAPSK "mypresharedkey"
#include "wifi_secrets.h"

// Should we use serial debugging? This adds messages to the serial console at 9600 baud.
// Use it until the sensor is calibrated and you have read out the IP address.
#define SERIALDEBUG

#define DHTPIN D4     // Sensor is attached to D4 (Wemos/Lolin D1 mini with DHT shield) 
#define DHTTYPE DHT11 // We are using an DHT11 sensor.

// Define some offsets. Since constantly polling the WiFi module warms it up, solutions
// like the D1 mini shield might require higher offsets.  
// Sensor offsets are typically +/- 2.5°C. 
#define T_OFFSET 4.5  // sensor shows 4.5°C higher than real value
#define H_OFFSET -2.0 // Sensor shows 2.0% lower than real value 

// Define some thresholds, these are taken from recommendations regarding office rooms, 
// for data centers you might allow a wider temperature range and prefer lower humidity.
// Temperature minimum:
#define T_MIN_WARN 17.0
#define T_MIN_CRIT 15.0
// Temperature maximum: 
#define T_MAX_WARN 24.0
#define T_MAX_CRIT 26.0
// Humidity minimum:
#define H_MIN_WARN 38.0
#define H_MIN_CRIT 34.0
// Humidity maximum:
#define H_MAX_WARN 62.0
#define H_MAX_CRIT 66.0

// Let's start a single server on port 6556, see:
// https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml?search=checkmk
WiFiServer server(6556);

// Create an object for the DHT sensor, this is available as "dht" 
DHT dht(DHTPIN, DHTTYPE);

// Prepare variables for humidity and temperature:
float humidity;
float temperature;

void setup() {
  // Initialize the DHT sensor
  dht.begin();
  // Start serial connection:
  #ifdef SERIALDEBUG
  Serial.begin(9600);
  Serial.print("Connecting to WiFi");
  #endif
  WiFi.begin(ESSID, WPAPSK);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    #ifdef SERIALDEBUG
    Serial.print(".");
    #endif
  }
  #ifdef SERIALDEBUG
  // Print out the IP settings to the serial console:
  Serial.println("");
  Serial.println("WiFi connected");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());
  #endif
  server.begin();
  // The sensor needs 1-2 seconds before the first readout is reliable.
  delay(2000);
}

void loop() {
  // Read out humidity and temperature and store to variables.
  humidity = dht.readHumidity();
  temperature = dht.readTemperature();
  #ifdef SERIALDEBUG
  // Try not to overflow the console. The delay slows down response time, so remove debugging later!
  delay(500);
  Serial.print("Humidity: "); //Im seriellen Monitor den Text und 
  Serial.print(humidity - H_OFFSET); //die Dazugehörigen Werte anzeigen
  Serial.println("% rel.");
  Serial.print("Temperature: ");
  Serial.print(temperature - T_OFFSET);
  Serial.println("°C");
  #endif
  WiFiClient client = server.available(); 
  // The Checkmk "protocol" is dead simple: As soon as a request is incoming, we answer it.
  // In http you'd wait for one empty line before answering, since this marks end of request.
  if (client) {
    #ifdef SERIALDEBUG
    Serial.println("Client available");
    #endif
    client.println("<<<check_mk>>>\nAgentOS: arduino");
    client.print("<<<dht_cmk_plugin>>>\ntemp ");
    client.println(temperature - T_OFFSET);
    client.print("humidity ");
    client.println(humidity - H_OFFSET);
    client.println("<<<local:sep(0)>>>");
    // Print out humidity
    if ((humidity - H_OFFSET) < H_MIN_CRIT) {
      client.print("2 \"DHT humidity\" humidity=");
      client.print(humidity - H_OFFSET);
      client.println(" Humidity is too dry");
    } else if ((humidity - H_OFFSET) > H_MAX_CRIT) {
      client.print("2 \"DHT humidity\" humidity=");
      client.print(humidity - H_OFFSET);
      client.println(" Humidity is too wet");
    } else if (H_MIN_CRIT <= (humidity - H_OFFSET) && (humidity - H_OFFSET) < H_MIN_WARN) {
      client.print("1 \"DHT humidity\" humidity=");
      client.print(humidity - H_OFFSET);
      client.println(" Humidity is a bit dry");
    } else if (H_MAX_CRIT >= (humidity - H_OFFSET) && (humidity - H_OFFSET) > H_MAX_WARN) {
      client.print("1 \"DHT humidity\" humidity=");
      client.print(humidity - H_OFFSET);
      client.println(" Humidity is a bit wet");
    }  else {
      client.print("0 \"DHT humidity\" humidity=");
      client.print(humidity - H_OFFSET);
      client.println(" Humidity is comfortable");
    }
    // Print out temperature
    if ((temperature - T_OFFSET) < T_MIN_CRIT) {
      client.print("2 \"DHT temperature\" temperature=");
      client.print(temperature - T_OFFSET);
      client.println(" Temperature  is too low");
    } else if ((temperature - T_OFFSET) > T_MAX_CRIT) {
      client.print("2 \"DHT temperature\" temperature=");
      client.print(temperature - T_OFFSET);
      client.println(" Temperature is too high");
    } else if (T_MIN_CRIT <= (temperature - T_OFFSET) && (temperature - T_OFFSET) < T_MIN_WARN) {
      client.print("1 \"DHT temperature\" temperature=");
      client.print(temperature - T_OFFSET);
      client.println(" Temperature is a bit low");
    } else if (T_MAX_CRIT >= (temperature - T_OFFSET) && (temperature - T_OFFSET) > T_MAX_WARN) {
      client.print("1 \"DHT temperature\" temperature=");
      client.print(temperature - T_OFFSET);
      client.println(" Temperature is a bit high");
    } else { 
      client.print("0 \"DHT temperature\" temperature=");
      client.print(temperature - T_OFFSET);
      client.println(" Temperature is comfortable");
    }
    // Die Verbindung beenden
    client.stop();
    #ifdef SERIALDEBUG
    Serial.println("Client disconnected");
    Serial.println("");
    #endif
  }
}
// Start the loop all over again…

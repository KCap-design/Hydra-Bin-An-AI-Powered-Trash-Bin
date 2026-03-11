#include <WiFi.h>
#include <PubSubClient.h>
#include <Stepper.h>
#include <ESP32Servo.h>

// --- Precise Motor Configuration ---
// The actual gear ratio of a 28BYJ-48 is 63.68395:1
// Total steps for 360 degrees = 32 (internal steps) * 63.68395 (ratio) = 2037.8864
const float stepsPer360 = 2037.8864; 
Stepper myStepper(2048, 12, 27, 14, 26); // Keep 2048 for the library initialization

// Variables to track "True Position"
float currentStepPosition = 0; 

// 360 Servo
Servo myServo;
const int servoPin = 25;

// --- Network Settings ---
const char* ssid = "PLDTHOMEFIBRj8cGb";
const char* password = "PLDTWIFI55kU2";
const char* mqtt_server = "broker.hivemq.com";
const int mqtt_port = 1883;
const char* mqtt_topic_result = "hydra_bin/classification_result";

WiFiClient espClient;
PubSubClient client(espClient);

void setup_wifi() {
  delay(10);
  Serial.println("\nConnecting to WiFi...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");
}

// Function to move to an EXACT angle and return
void dropWasteAtAngle(float targetAngle) {
  // 1. Calculate steps needed for that specific angle using the precise constant
  int targetSteps = round((targetAngle / 360.0) * stepsPer360);
  
  // 2. Move from current 0 to Target
  Serial.printf("Moving to %.1f degrees (%d steps)...\n", targetAngle, targetSteps);
  myStepper.step(targetSteps);
  delay(500);

  // 3. Drop mechanism (360 Servo)
  Serial.println("Activating Servo...");
  myServo.write(180); // Full speed rotation
  delay(1500);        // Adjust this for how long the trapdoor stays open
  myServo.write(90);  // Stop (Most 360 servos stop at 90 or 0, test yours!)
  delay(500);

  // 4. Return EXACTLY the same number of steps to ensure 0 is preserved
  Serial.println("Returning to Home...");
  myStepper.step(-targetSteps);
  Serial.println("Ready for next item.");
}

void callback(char* topic, byte* payload, unsigned int length) {
  String messageTemp;
  for (int i = 0; i < length; i++) {
    messageTemp += (char)payload[i];
  }
  
  Serial.print("Message arrived: ");
  Serial.println(messageTemp);

  if (String(topic) == mqtt_topic_result) {
    if(messageTemp == "biodegradable") {
      dropWasteAtAngle(90.0);
    }
    else if(messageTemp == "landfills") {
      dropWasteAtAngle(0);
    }
    else if(messageTemp == "recyclable") {
      dropWasteAtAngle(270.0);
    }
  }
}

void reconnect() {
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection...");
    String clientId = "ESP32Client-" + String(random(0xffff), HEX);
    if (client.connect(clientId.c_str())) {
      Serial.println("connected");
      client.subscribe(mqtt_topic_result);
    } else {
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  
  // Initialize Motors
  myStepper.setSpeed(15); 
  myServo.attach(servoPin);
  myServo.write(90); // Most 360 servos use 90 as "Stop"
  
  // Reminder for the user
  Serial.println("!!! MANUAL ALIGNMENT REQUIRED !!!");
  Serial.println("Ensure bin is at 0 degrees before connecting...");

  setup_wifi();
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();
}
#include <Arduino.h>
#include <ESP32Servo.h>
#include <WiFi.h>
#include <ArduinoWebsockets.h>

using namespace websockets;

#define TRIG1 5
#define ECHO1 18
#define TRIG2 2
#define ECHO2 15
#define SERVO_PIN 4

const char* ssid = "DUUU";  // Thay bằng WiFi của bạn
const char* password = "12345678";
const char* wsServer = "ws://192.168.0.103:3001"; // Địa chỉ server WebSocket

Servo gateServo;
WebsocketsClient client;
int totalSlots = 3;
int occupiedSlots = 0;
unsigned long lastReconnectAttempt = 0;

void setup() {
    Serial.begin(115200);
    pinMode(TRIG1, OUTPUT);
    pinMode(ECHO1, INPUT);
    pinMode(TRIG2, OUTPUT);
    pinMode(ECHO2, INPUT);
    gateServo.attach(SERVO_PIN);
    gateServo.write(0);

    WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(1000);
        Serial.println("Connecting to WiFi...");
    }
    Serial.println("Connected to WiFi!");

    connectWebSocket();
}

void connectWebSocket() {
    if (client.connect(wsServer)) {
        Serial.println("WebSocket connected!");
    } else {
        Serial.println("WebSocket connection failed!");
    }

    client.onMessage([](WebsocketsMessage message) {
        Serial.println("Received from server: " + message.data());
    });
}

long measureDistance(int trigPin, int echoPin) {
    digitalWrite(trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);
    long duration = pulseIn(echoPin, HIGH);
    long distance = duration * 0.034 / 2;
    return distance;
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi disconnected! Reconnecting...");
        WiFi.begin(ssid, password);
        delay(5000);
    }

    if (!client.available()) {
        unsigned long now = millis();
        if (now - lastReconnectAttempt > 5000) { // Thử kết nối lại mỗi 5 giây
            Serial.println("WebSocket disconnected! Reconnecting...");
            connectWebSocket();
            lastReconnectAttempt = now;
        }
    }

    long distance2 = measureDistance(TRIG1, ECHO1);
    long distance1 = measureDistance(TRIG2, ECHO2);

    if (distance1 < 10 && occupiedSlots < totalSlots) {
        gateServo.write(90);
        occupiedSlots++;
        delay(2000);
        
        gateServo.write(0);
    } else if (distance2 < 10 && occupiedSlots > 0) {
        gateServo.write(90);
        occupiedSlots--;
        delay(2000);
        
        gateServo.write(0);
    }

    String message = "{\"occupiedSlots\":" + String(occupiedSlots) +
                     ", \"totalSlots\":" + String(totalSlots) + "}";

    Serial.println("Sending: " + message);
    
    if (client.available()) {
        client.send(message);
    }

    client.poll();
    delay(500);
}

#include <Arduino.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <RTClib.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <time.h>

#if defined(GARDENJOURNAL_PROFILE_STORAGE_01)
#include "secrets.storage.h"
#else
#include "secrets.h"
#endif

#ifndef GARDENJOURNAL_CLOUD_ENABLED
#define GARDENJOURNAL_CLOUD_ENABLED 0
#endif
#ifndef GARDENJOURNAL_CLOUD_BASE_URL
#define GARDENJOURNAL_CLOUD_BASE_URL ""
#endif
#ifndef GARDENJOURNAL_CLOUD_DEVICE_TOKEN
#define GARDENJOURNAL_CLOUD_DEVICE_TOKEN ""
#endif
#ifndef GARDENJOURNAL_CLOUD_ROOT_CA
#define GARDENJOURNAL_CLOUD_ROOT_CA ""
#endif
#ifndef GARDENJOURNAL_CLOUD_DEVICE_ID
#define GARDENJOURNAL_CLOUD_DEVICE_ID ""
#endif

// ─── Matériel ───────────────────────────────────────────────────────────────
// Le SHT40 et le HW-84 / DS3231 partagent le même bus I2C.
constexpr uint8_t I2C_SDA_PIN = 21;
constexpr uint8_t I2C_SCL_PIN = 22;
constexpr uint8_t SHT40_I2C_ADDRESS = 0x44;
constexpr uint8_t SHT40_MEASURE_HIGH_PRECISION = 0xFD;

// GPIO34 appartient à ADC1 : sa lecture reste disponible quand le Wi-Fi est
// actif. Il s'agit d'une entrée uniquement, ce qui convient au capteur lumière.
constexpr uint8_t LIGHT_ADC_PIN = 34;

enum class LightSensorType : uint8_t {
  none,
  temt6000,
  photoresistor,
};

#if defined(GARDENJOURNAL_PROFILE_STORAGE_01)
constexpr LightSensorType LIGHT_SENSOR_TYPE = LightSensorType::none;
#else
constexpr LightSensorType LIGHT_SENSOR_TYPE = LightSensorType::photoresistor;
#endif
constexpr uint16_t LIGHT_ON_THRESHOLD = 1200;
constexpr uint16_t LIGHT_OFF_THRESHOLD = 800;
constexpr uint8_t LIGHT_SAMPLE_COUNT = 16;
static_assert(LIGHT_ON_THRESHOLD > LIGHT_OFF_THRESHOLD,
              "Le seuil ON doit être supérieur au seuil OFF");

RTC_DS3231 rtc;

// ─── Identité et réseau ─────────────────────────────────────────────────────
#if defined(GARDENJOURNAL_PROFILE_STORAGE_01)
constexpr char DEVICE_ID[] = "storage-01";
constexpr char HOSTNAME[] = "gardenjournal-storage-01";
constexpr char FIRMWARE_VERSION[] = "0.3.4-sht40-storage-wifi-diagnostics";
#else
constexpr char DEVICE_ID[] = "culture-ldr-01";
constexpr char HOSTNAME[] = "gardenjournal-culture-ldr-01";
constexpr char FIRMWARE_VERSION[] = "0.3.4-sht40-light-wifi-diagnostics";
#endif
constexpr uint16_t HTTP_PORT = 80;

WebServer server(HTTP_PORT);
Preferences preferences;

// ─── Mesures ────────────────────────────────────────────────────────────────
constexpr unsigned long SENSOR_INTERVAL_MS = 2000;
constexpr unsigned long SHT40_RETRY_INTERVAL_MS = 10000;
constexpr unsigned long HISTORY_INTERVAL_MS = 60000;
constexpr unsigned long CLOUD_UPLOAD_INTERVAL_MS = 60000;
constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 30000;

struct HistoryRecord {
  uint32_t timestamp;
  float temperature;
  float humidity;
  float vpd;
  uint16_t lightRaw;
  // 0 = éteint, 1 = allumé, 2 = aucun capteur lumière configuré.
  uint8_t lightState;
  uint8_t reserved;
};

struct CloudOutboxRecord {
  uint32_t sequence;
  uint32_t timestamp;
  float temperature;
  float humidity;
  float vpd;
};

// Environ 14 jours à raison d'un point par minute.
constexpr uint32_t MAX_HISTORY_RECORDS = 14 * 24 * 60;
// Fichiers distincts de l'ancien firmware DHT : les structures binaires ne
// sont pas compatibles et l'ancien historique ne doit pas être interprété.
constexpr char HISTORY_FILE[] = "/readings_sht40_v1.bin";
constexpr char CLOUD_OUTBOX_FILE[] = "/cloud_sht40_v1.bin";
constexpr char PREF_NAMESPACE[] = "sht40hist";
constexpr uint32_t MAX_CLOUD_OUTBOX_RECORDS = MAX_HISTORY_RECORDS;
constexpr uint8_t CLOUD_BATCH_SIZE = 20;

uint32_t historyCount = 0;
uint32_t historyNextIndex = 0;
uint32_t cloudOutboxCount = 0;
uint32_t cloudOutboxHead = 0;
uint32_t cloudNextSequence = 1;

unsigned long lastSensorRead = 0;
unsigned long lastSht40Attempt = 0;
unsigned long lastHistoryWrite = 0;
unsigned long lastWifiAttempt = 0;
unsigned long lastCloudUpload = 0;
bool wifiAttemptStarted = false;
bool networkServicesStarted = false;
bool rtcAvailable = false;
bool sht40Available = false;
bool historyStorageAvailable = false;
bool hasReading = false;
float temperature = NAN;
float humidity = NAN;
float vpd = NAN;
uint16_t lightRaw = 0;
bool lightOn = false;
bool lightStateKnown = false;
uint32_t lastTimestamp = 0;

bool hasLightSensor() {
  return LIGHT_SENSOR_TYPE != LightSensorType::none;
}

const char* lightSensorName() {
  switch (LIGHT_SENSOR_TYPE) {
    case LightSensorType::temt6000:
      return "TEMT6000";
    case LightSensorType::photoresistor:
      return "photoresistance";
    case LightSensorType::none:
      return "aucun";
  }
  return "inconnu";
}

uint8_t currentLightState() {
  if (!hasLightSensor() || !lightStateKnown) return 2;
  return lightOn ? 1 : 0;
}

void scanI2cBus() {
  uint8_t found = 0;
  Serial.println("Scan I2C :");
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    const uint8_t error = Wire.endTransmission();
    if (error == 0) {
      Serial.printf("  0x%02X detecte\n", address);
      found++;
    }
  }
  if (found == 0) Serial.println("  aucun peripherique I2C");
}

bool i2cDeviceAvailable(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

uint8_t sht40Crc(const uint8_t* data, uint8_t length) {
  uint8_t crc = 0xFF;
  for (uint8_t index = 0; index < length; index++) {
    crc ^= data[index];
    for (uint8_t bit = 0; bit < 8; bit++) {
      crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x31)
                         : static_cast<uint8_t>(crc << 1);
    }
  }
  return crc;
}

bool readSht40(float& nextTemperature, float& nextHumidity) {
  Wire.beginTransmission(SHT40_I2C_ADDRESS);
  Wire.write(SHT40_MEASURE_HIGH_PRECISION);
  if (Wire.endTransmission() != 0) return false;

  delay(10);
  if (Wire.requestFrom(SHT40_I2C_ADDRESS, static_cast<uint8_t>(6)) != 6) {
    return false;
  }

  uint8_t data[6];
  for (uint8_t index = 0; index < sizeof(data); index++) {
    data[index] = Wire.read();
  }
  if (sht40Crc(data, 2) != data[2] || sht40Crc(data + 3, 2) != data[5]) {
    return false;
  }

  const uint16_t rawTemperature =
      (static_cast<uint16_t>(data[0]) << 8) | data[1];
  const uint16_t rawHumidity =
      (static_cast<uint16_t>(data[3]) << 8) | data[4];
  nextTemperature = -45.0f + 175.0f * rawTemperature / 65535.0f;
  nextHumidity = constrain(-6.0f + 125.0f * rawHumidity / 65535.0f,
                           0.0f, 100.0f);
  return true;
}

void detectSht40(bool announceMissing) {
  const bool wasAvailable = sht40Available;
  sht40Available = i2cDeviceAvailable(SHT40_I2C_ADDRESS);
  lastSht40Attempt = millis();
  if (sht40Available && !wasAvailable) {
    Serial.println("SHT40 detecte");
  } else if (!sht40Available && announceMissing) {
    Serial.println("SHT40 absent (normal tant que le capteur n'est pas branche)");
  }
}

bool cloudConfigured() {
#if GARDENJOURNAL_CLOUD_ENABLED
  return String(GARDENJOURNAL_CLOUD_BASE_URL).startsWith("https://") &&
         strlen(GARDENJOURNAL_CLOUD_DEVICE_ID) > 0 &&
         strlen(GARDENJOURNAL_CLOUD_DEVICE_TOKEN) > 0 &&
         strlen(GARDENJOURNAL_CLOUD_ROOT_CA) > 0;
#else
  return false;
#endif
}

float saturationPressure(float temp) {
  return 0.6108f * exp((17.27f * temp) / (temp + 237.3f));
}

float calculateVpd(float temp, float hum) {
  return saturationPressure(temp) * (1.0f - hum / 100.0f);
}

float calculateDewPoint(float temp, float hum) {
  const float safeHumidity = constrain(hum, 0.1f, 100.0f);
  const float gamma = log(safeHumidity / 100.0f) +
                      (17.62f * temp) / (243.12f + temp);
  return 243.12f * gamma / (17.62f - gamma);
}

bool clockIsValid() {
  time_t now;
  time(&now);
  return now >= 1577836800 ||
         (rtcAvailable && rtc.now().unixtime() >= 1577836800);
}

bool rtcClockIsValid() {
  if (!rtcAvailable) return false;
  return rtc.now().unixtime() >= 1577836800;
}

uint32_t currentTimestamp() {
  time_t now;
  time(&now);
  if (rtcClockIsValid()) return rtc.now().unixtime();
  return static_cast<uint32_t>(now);
}

void syncRtcFromNetworkTime() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  struct tm timeInfo;
  if (!getLocalTime(&timeInfo, 10000)) {
    Serial.println("NTP indisponible ; horloge DS3231 conservee");
    return;
  }

  time_t networkTime;
  time(&networkTime);
  if (rtcAvailable) {
    rtc.adjust(DateTime(static_cast<uint32_t>(networkTime)));
    Serial.println("Horloge DS3231 synchronisee par NTP");
  }
}

void loadHistoryState() {
  File file = LittleFS.open(HISTORY_FILE, FILE_READ);
  const size_t fileSize = file ? file.size() : 0;
  if (file) file.close();

  const uint32_t fileCount = fileSize / sizeof(HistoryRecord);
  historyCount = min(fileCount, MAX_HISTORY_RECORDS);
  historyNextIndex = historyCount == MAX_HISTORY_RECORDS
                         ? preferences.getUInt("next", 0)
                         : historyCount;
  if (historyNextIndex >= MAX_HISTORY_RECORDS) historyNextIndex = 0;
}

void loadCloudOutboxState() {
  if (!cloudConfigured()) return;

  File file = LittleFS.open(CLOUD_OUTBOX_FILE, FILE_READ);
  const size_t fileSize = file ? file.size() : 0;
  if (file) file.close();

  const uint32_t fileRecords = fileSize / sizeof(CloudOutboxRecord);
  const uint32_t savedCount =
      preferences.getUInt("cloud_count", fileRecords);
  cloudOutboxCount = min(min(savedCount, fileRecords), MAX_CLOUD_OUTBOX_RECORDS);
  cloudOutboxHead = preferences.getUInt("cloud_head", 0);
  cloudNextSequence = preferences.getUInt("cloud_next", 1);
  if (cloudOutboxHead >= MAX_CLOUD_OUTBOX_RECORDS) cloudOutboxHead = 0;
  if (cloudNextSequence == 0) cloudNextSequence = 1;
  if (cloudOutboxCount == 0) cloudOutboxHead = 0;
}

bool appendCloudOutbox(const CloudOutboxRecord& record) {
  if (!historyStorageAvailable || !cloudConfigured() ||
      cloudOutboxCount >= MAX_CLOUD_OUTBOX_RECORDS) {
    return false;
  }

  const uint32_t slot =
      (cloudOutboxHead + cloudOutboxCount) % MAX_CLOUD_OUTBOX_RECORDS;
  File file = LittleFS.exists(CLOUD_OUTBOX_FILE)
                  ? LittleFS.open(CLOUD_OUTBOX_FILE, "r+")
                  : LittleFS.open(CLOUD_OUTBOX_FILE, FILE_WRITE);
  if (!file || !file.seek(slot * sizeof(CloudOutboxRecord), SeekSet)) {
    if (file) file.close();
    return false;
  }
  const size_t written = file.write(
      reinterpret_cast<const uint8_t*>(&record), sizeof(CloudOutboxRecord));
  file.close();
  if (written != sizeof(CloudOutboxRecord)) return false;

  cloudOutboxCount++;
  cloudNextSequence = record.sequence + 1;
  preferences.putUInt("cloud_count", cloudOutboxCount);
  preferences.putUInt("cloud_head", cloudOutboxHead);
  preferences.putUInt("cloud_next", cloudNextSequence);
  return true;
}

bool readCloudOutboxRecord(uint32_t slot, CloudOutboxRecord& record) {
  if (slot >= MAX_CLOUD_OUTBOX_RECORDS) return false;
  File file = LittleFS.open(CLOUD_OUTBOX_FILE, FILE_READ);
  if (!file || !file.seek(slot * sizeof(CloudOutboxRecord), SeekSet)) {
    if (file) file.close();
    return false;
  }
  const bool readComplete =
      file.read(reinterpret_cast<uint8_t*>(&record), sizeof(CloudOutboxRecord)) ==
      sizeof(CloudOutboxRecord);
  file.close();
  return readComplete;
}

void acknowledgeCloudThrough(uint32_t acceptedThrough) {
  while (cloudOutboxCount > 0) {
    CloudOutboxRecord record;
    if (!readCloudOutboxRecord(cloudOutboxHead, record)) return;
    if (record.sequence > acceptedThrough) break;
    cloudOutboxHead = (cloudOutboxHead + 1) % MAX_CLOUD_OUTBOX_RECORDS;
    cloudOutboxCount--;
  }
  preferences.putUInt("cloud_count", cloudOutboxCount);
  preferences.putUInt("cloud_head", cloudOutboxHead);
}

String cloudEventId(uint32_t sequence) {
  String eventId = GARDENJOURNAL_CLOUD_DEVICE_ID;
  eventId += '-';
  eventId += String(sequence);
  return eventId;
}

String cloudTelemetryPayload() {
  String payload;
  payload.reserve(3200);
  payload += F("{\"schema\":1,\"deviceId\":\"");
  payload += GARDENJOURNAL_CLOUD_DEVICE_ID;
  payload += F("\",\"firmwareVersion\":\"");
  payload += FIRMWARE_VERSION;
  payload += F("\",\"readings\":[");

  uint8_t added = 0;
  for (uint8_t offset = 0;
       offset < cloudOutboxCount && added < CLOUD_BATCH_SIZE; offset++) {
    const uint32_t slot =
        (cloudOutboxHead + offset) % MAX_CLOUD_OUTBOX_RECORDS;
    CloudOutboxRecord record;
    if (!readCloudOutboxRecord(slot, record)) break;
    if (added > 0) payload += ',';
    payload += F("{\"eventId\":\"");
    payload += cloudEventId(record.sequence);
    payload += F("\",\"sequence\":");
    payload += String(record.sequence);
    payload += F(",\"timestamp\":");
    payload += String(record.timestamp);
    payload += F(",\"temperature\":");
    payload += String(record.temperature, 2);
    payload += F(",\"humidity\":");
    payload += String(record.humidity, 2);
    payload += F(",\"vpd\":");
    payload += String(record.vpd, 3);
    payload += '}';
    added++;
  }
  payload += F("]}");
  return payload;
}

bool parseAcceptedThrough(const String& response, uint32_t& acceptedThrough) {
  const int key = response.indexOf(F("\"acceptedThrough\""));
  if (key < 0) return false;
  const int colon = response.indexOf(':', key);
  if (colon < 0) return false;
  int start = colon + 1;
  while (start < response.length() &&
         (response[start] == ' ' || response[start] == '\t')) {
    start++;
  }
  if (start >= response.length() || response[start] < '0' ||
      response[start] > '9') {
    return false;
  }
  char* end = nullptr;
  const unsigned long parsed = strtoul(response.c_str() + start, &end, 10);
  if (end == response.c_str() + start || parsed > 0xFFFFFFFFUL) return false;
  acceptedThrough = static_cast<uint32_t>(parsed);
  return true;
}

void flushCloudOutbox() {
#if GARDENJOURNAL_CLOUD_ENABLED
  if (!cloudConfigured() || WiFi.status() != WL_CONNECTED ||
      cloudOutboxCount == 0 ||
      millis() - lastCloudUpload < CLOUD_UPLOAD_INTERVAL_MS) {
    return;
  }
  lastCloudUpload = millis();

  WiFiClientSecure tlsClient;
  tlsClient.setCACert(GARDENJOURNAL_CLOUD_ROOT_CA);
  HTTPClient http;
  String url = GARDENJOURNAL_CLOUD_BASE_URL;
  if (url.endsWith("/")) url.remove(url.length() - 1);
  url += F("/api/v1/devices/");
  url += GARDENJOURNAL_CLOUD_DEVICE_ID;
  url += F("/telemetry");
  if (!http.begin(tlsClient, url)) {
    Serial.println("Cloud: ouverture HTTPS impossible");
    return;
  }
  http.addHeader("Authorization", String("Bearer ") +
                                      GARDENJOURNAL_CLOUD_DEVICE_TOKEN);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  const String payload = cloudTelemetryPayload();
  const int status = http.POST(payload);
  const String response = http.getString();
  http.end();

  uint32_t acceptedThrough = 0;
  if (status < 200 || status >= 300 ||
      !parseAcceptedThrough(response, acceptedThrough)) {
    Serial.printf("Cloud: envoi reporte (HTTP %d)\n", status);
    return;
  }
  acknowledgeCloudThrough(acceptedThrough);
  Serial.printf("Cloud: accuse jusqu'a %lu, reste %lu\n",
                static_cast<unsigned long>(acceptedThrough),
                static_cast<unsigned long>(cloudOutboxCount));
#endif
}

bool saveHistoryRecord() {
  if (!historyStorageAvailable || !hasReading || !clockIsValid()) return false;

  HistoryRecord record{
      .timestamp = lastTimestamp,
      .temperature = temperature,
      .humidity = humidity,
      .vpd = vpd,
      .lightRaw = lightRaw,
      .lightState = currentLightState(),
      .reserved = 0,
  };

  File file;
  if (historyCount < MAX_HISTORY_RECORDS) {
    file = LittleFS.open(HISTORY_FILE, FILE_APPEND);
    if (!file) file = LittleFS.open(HISTORY_FILE, FILE_WRITE);
  } else {
    // r+ permet d'écraser le plus ancien point sans reconstruire tout le
    // fichier et limite l'usage de la mémoire RAM.
    file = LittleFS.open(HISTORY_FILE, "r+");
    if (file &&
        !file.seek(historyNextIndex * sizeof(HistoryRecord), SeekSet)) {
      file.close();
      return false;
    }
  }

  if (!file) return false;
  const size_t written = file.write(
      reinterpret_cast<const uint8_t*>(&record), sizeof(HistoryRecord));
  file.close();
  if (written != sizeof(HistoryRecord)) return false;

  if (historyCount < MAX_HISTORY_RECORDS) {
    historyCount++;
    historyNextIndex = historyCount == MAX_HISTORY_RECORDS ? 0 : historyCount;
  } else {
    historyNextIndex = (historyNextIndex + 1) % MAX_HISTORY_RECORDS;
  }
  preferences.putUInt("next", historyNextIndex);
  const CloudOutboxRecord cloudRecord{
      .sequence = cloudNextSequence,
      .timestamp = record.timestamp,
      .temperature = record.temperature,
      .humidity = record.humidity,
      .vpd = record.vpd,
  };
  if (cloudConfigured() && !appendCloudOutbox(cloudRecord)) {
    Serial.println("Cloud: file d'attente pleine ou indisponible");
  }
  return true;
}

String readingJson(uint32_t timestamp, float temp, float hum, float readingVpd,
                   uint16_t readingLightRaw, uint8_t readingLightState,
                   bool includeLightMetadata) {
  String json;
  json.reserve(includeLightMetadata ? 850 : 480);
  json += F("{\"deviceId\":\"");
  json += DEVICE_ID;
  json += F("\",\"timestamp\":");
  json += timestamp;
  json += F(",\"temperature\":");
  json += String(temp, 2);
  json += F(",\"humidity\":");
  json += String(hum, 2);
  json += F(",\"vpd\":");
  json += String(readingVpd, 3);
  json += F(",\"dewPoint\":");
  json += String(calculateDewPoint(temp, hum), 2);
  if (readingLightState != 2) {
    const bool readingLightOn = readingLightState == 1;
    json += F(",\"lightOn\":");
    json += readingLightOn ? F("true") : F("false");
    json += F(",\"lightRaw\":");
    json += readingLightRaw;
    if (includeLightMetadata) {
      json += F(",\"capabilities\":{");
      json += F("\"light_adc_raw\":{\"type\":\"number\","
                "\"label\":\"Lumiere brute\",\"unit\":\"ADC\","
                "\"min\":0,\"max\":4095},");
      json += F("\"light_detected\":{\"type\":\"boolean\","
                "\"label\":\"Eclairage detecte\"}},");
      json += F("\"measurements\":{\"light_adc_raw\":{\"value\":");
      json += readingLightRaw;
      json += F(",\"unit\":\"ADC\",\"quality\":\"uncalibrated\"},"
                "\"light_detected\":");
      json += readingLightOn ? F("true") : F("false");
      json += F("}");
    }
  }
  // This breadboard has no mist output: do not report a fabricated OFF state.
  json += F(",\"mode\":\"TEST\"");
  json += F(",\"rssi\":");
  if (WiFi.status() == WL_CONNECTED) {
    json += WiFi.RSSI();
  } else {
    json += F("null");
  }
  json += F(",\"firmwareVersion\":\"");
  json += FIRMWARE_VERSION;
  json += F("\"}");
  return json;
}

bool readHistoryRecord(File& file, uint32_t index, HistoryRecord& record) {
  if (!file.seek(index * sizeof(HistoryRecord), SeekSet)) return false;
  return file.read(reinterpret_cast<uint8_t*>(&record), sizeof(HistoryRecord)) ==
         sizeof(HistoryRecord);
}

void handleStatus() {
  if (!sht40Available) {
    server.send(503, "application/json",
                "{\"error\":\"sht40_not_ready\",\"diagnostics\":\"/diagnostics\"}");
    return;
  }
  if (!hasReading) {
    server.send(503, "application/json",
                "{\"error\":\"sensor_reading_not_ready\"}");
    return;
  }
  if (!clockIsValid()) {
    server.send(503, "application/json",
                "{\"error\":\"clock_not_ready\",\"diagnostics\":\"/diagnostics\"}");
    return;
  }
  server.send(200, "application/json",
              readingJson(lastTimestamp, temperature, humidity, vpd,
                          lightRaw, currentLightState(), true));
}

void handleDiagnostics() {
  const bool validClock = clockIsValid();
  String json;
  json.reserve(600);
  json += F("{\"deviceId\":\"");
  json += DEVICE_ID;
  json += F("\",\"firmwareVersion\":\"");
  json += FIRMWARE_VERSION;
  json += F("\",\"sht40Detected\":");
  json += sht40Available ? F("true") : F("false");
  json += F(",\"rtcDetected\":");
  json += rtcAvailable ? F("true") : F("false");
  json += F(",\"clockValid\":");
  json += validClock ? F("true") : F("false");
  json += F(",\"clockSource\":\"");
  if (rtcClockIsValid()) {
    json += F("DS3231");
  } else if (validClock) {
    json += F("NTP");
  } else {
    json += F("none");
  }
  json += F("\",\"timestamp\":");
  if (validClock) {
    json += currentTimestamp();
  } else {
    json += F("null");
  }
  json += F(",\"rtcTemperatureC\":");
  if (rtcAvailable) {
    json += String(rtc.getTemperature(), 2);
  } else {
    json += F("null");
  }
  json += F(",\"lightSensor\":\"");
  json += lightSensorName();
  json += F("\",\"lightRaw\":");
  if (hasLightSensor() && lightStateKnown) {
    json += lightRaw;
  } else {
    json += F("null");
  }
  json += F(",\"lightOn\":");
  if (hasLightSensor() && lightStateKnown) {
    json += lightOn ? F("true") : F("false");
  } else {
    json += F("null");
  }
  json += F(",\"wifiConnected\":");
  json += WiFi.status() == WL_CONNECTED ? F("true") : F("false");
  json += F(",\"historyStorageReady\":");
  json += historyStorageAvailable ? F("true") : F("false");
  json += F(",\"rssi\":");
  if (WiFi.status() == WL_CONNECTED) {
    json += WiFi.RSSI();
  } else {
    json += F("null");
  }
  json += F(",\"i2cSdaPin\":21,\"i2cSclPin\":22,\"lightAdcPin\":34}");
  server.send(200, "application/json", json);
}

void handleReadings() {
  if (!historyStorageAvailable) {
    server.send(503, "application/json",
                "{\"error\":\"history_storage_unavailable\"}");
    return;
  }
  long requestedSince = server.hasArg("since") ? server.arg("since").toInt()
                                                : 0;
  if (requestedSince < 0) requestedSince = 0;

  File file = LittleFS.open(HISTORY_FILE, FILE_READ);
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.send(200, "application/json", "[");

  bool first = true;
  if (file) {
    const uint32_t start = historyCount == MAX_HISTORY_RECORDS
                               ? historyNextIndex
                               : 0;
    for (uint32_t offset = 0; offset < historyCount; offset++) {
      const uint32_t index =
          historyCount == MAX_HISTORY_RECORDS
              ? (start + offset) % MAX_HISTORY_RECORDS
              : offset;
      HistoryRecord record;
      if (!readHistoryRecord(file, index, record) ||
          record.timestamp <= static_cast<uint32_t>(requestedSince)) {
        continue;
      }
      if (!first) server.sendContent(",");
      server.sendContent(
          readingJson(record.timestamp, record.temperature, record.humidity,
                      record.vpd, record.lightRaw, record.lightState, false));
      first = false;
    }
    file.close();
  }
  server.sendContent("]");
}

void handleUnsupportedConfig() {
  server.send(501, "application/json",
              "{\"status\":\"unsupported\",\"reason\":\"no_actuator_in_breadboard_test\"}");
}

void handleNotFound() {
  server.send(404, "application/json", "{\"error\":\"not_found\"}");
}

void startNetworkServices() {
  if (networkServicesStarted || WiFi.status() != WL_CONNECTED) return;

  syncRtcFromNetworkTime();
  if (MDNS.begin(HOSTNAME)) MDNS.addService("http", "tcp", HTTP_PORT);

  server.on("/status", HTTP_GET, handleStatus);
  server.on("/diagnostics", HTTP_GET, handleDiagnostics);
  server.on("/readings", HTTP_GET, handleReadings);
  server.on("/config", HTTP_POST, handleUnsupportedConfig);
  server.onNotFound(handleNotFound);
  server.begin();
  networkServicesStarted = true;

  Serial.print("Wi-Fi connecte, IP: http://");
  Serial.println(WiFi.localIP());
  Serial.print("Adresse MAC: ");
  Serial.println(WiFi.macAddress());
  Serial.print("Nom mDNS: http://");
  Serial.print(HOSTNAME);
  Serial.println(".local");
}

void handleWifiEvent(arduino_event_id_t event, arduino_event_info_t info) {
  if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    Serial.printf("Wi-Fi deconnecte, code raison: %u\n",
                  info.wifi_sta_disconnected.reason);
  }
}

void scanConfiguredWifi() {
  Serial.println("Recherche du reseau Wi-Fi configure...");
  const int16_t networkCount = WiFi.scanNetworks(false, true);
  if (networkCount < 0) {
    Serial.printf("Scan Wi-Fi impossible, code: %d\n", networkCount);
    return;
  }

  bool configuredNetworkFound = false;
  int32_t configuredNetworkRssi = 0;
  int32_t configuredNetworkChannel = 0;
  for (int16_t index = 0; index < networkCount; index++) {
    if (WiFi.SSID(index) == WIFI_SSID) {
      configuredNetworkFound = true;
      configuredNetworkRssi = WiFi.RSSI(index);
      configuredNetworkChannel = WiFi.channel(index);
      break;
    }
  }
  WiFi.scanDelete();

  if (configuredNetworkFound) {
    Serial.printf("Reseau Wi-Fi configure visible, RSSI %ld dBm, canal %ld\n",
                  static_cast<long>(configuredNetworkRssi),
                  static_cast<long>(configuredNetworkChannel));
  } else {
    Serial.printf("Reseau Wi-Fi configure introuvable parmi %d reseaux\n",
                  networkCount);
  }
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) {
    startNetworkServices();
    return;
  }

  if (wifiAttemptStarted &&
      millis() - lastWifiAttempt < WIFI_RETRY_INTERVAL_MS) {
    return;
  }
  if (wifiAttemptStarted) {
    WiFi.disconnect(false, false);
    delay(100);
  }
  lastWifiAttempt = millis();
  wifiAttemptStarted = true;
  Serial.print("Connexion Wi-Fi a ");
  Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void readLightSensor() {
  if (!hasLightSensor()) {
    lightRaw = 0;
    lightOn = false;
    lightStateKnown = false;
    return;
  }

  uint32_t total = 0;
  for (uint8_t index = 0; index < LIGHT_SAMPLE_COUNT; index++) {
    total += analogRead(LIGHT_ADC_PIN);
  }
  lightRaw = static_cast<uint16_t>(total / LIGHT_SAMPLE_COUNT);

  if (!lightStateKnown) {
    lightOn = lightRaw >= LIGHT_ON_THRESHOLD;
    lightStateKnown = true;
  } else if (!lightOn && lightRaw >= LIGHT_ON_THRESHOLD) {
    lightOn = true;
  } else if (lightOn && lightRaw <= LIGHT_OFF_THRESHOLD) {
    lightOn = false;
  }
}

void readSensor() {
  readLightSensor();
  lastTimestamp = clockIsValid() ? currentTimestamp() : 0;

  if (!sht40Available &&
      millis() - lastSht40Attempt >= SHT40_RETRY_INTERVAL_MS) {
    detectSht40(false);
  }

  if (!sht40Available) {
    if (hasLightSensor()) {
      Serial.printf("Lumiere %u (%s) | DS3231 %s | SHT40 absent\n", lightRaw,
                    lightOn ? "ON" : "OFF",
                    rtcClockIsValid() ? "OK" : "heure invalide");
    } else {
      Serial.printf("DS3231 %s | SHT40 absent\n",
                    rtcClockIsValid() ? "OK" : "heure invalide");
    }
    return;
  }

  float nextTemperature = NAN;
  float nextHumidity = NAN;
  if (!readSht40(nextTemperature, nextHumidity)) {
    Serial.println("Lecture SHT40 invalide");
    return;
  }
  if (isnan(nextHumidity) || isnan(nextTemperature)) {
    Serial.println("Valeur SHT40 non numerique");
    return;
  }

  humidity = nextHumidity;
  temperature = nextTemperature;
  vpd = calculateVpd(temperature, humidity);
  hasReading = true;

  if (hasLightSensor()) {
    Serial.printf("T %.1f C | HR %.1f %% | VPD %.2f kPa | Lumiere %u (%s)\n",
                  temperature, humidity, vpd, lightRaw,
                  lightOn ? "ON" : "OFF");
  } else {
    Serial.printf("T %.1f C | HR %.1f %% | VPD %.2f kPa\n", temperature,
                  humidity, vpd);
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000);
  scanI2cBus();

  detectSht40(true);

  rtcAvailable = rtc.begin();
  if (!rtcAvailable) {
    Serial.println("HW-84 / DS3231 introuvable ; NTP sera utilise si disponible");
  } else if (rtc.lostPower() || !rtcClockIsValid()) {
    // Heure de secours : elle rend immédiatement l'horodatage utilisable sans
    // Wi-Fi. La première connexion NTP corrigera ensuite l'heure précisément.
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    Serial.println("DS3231 initialise avec l'heure de compilation ; correction NTP en attente");
  } else {
    Serial.println("HW-84 / DS3231 detecte");
  }

  if (hasLightSensor()) {
    pinMode(LIGHT_ADC_PIN, INPUT);
    analogReadResolution(12);
    analogSetPinAttenuation(LIGHT_ADC_PIN, ADC_11db);
    Serial.printf("Capteur lumiere %s sur GPIO%u ; seuils OFF=%u ON=%u\n",
                  lightSensorName(), LIGHT_ADC_PIN, LIGHT_OFF_THRESHOLD,
                  LIGHT_ON_THRESHOLD);
  } else {
    Serial.println("Mesure de lumiere desactivee pour cette station");
  }

  // Ne jamais reformater automatiquement : l'historique local est une donnée
  // utilisateur et doit survivre aux mises à jour du sketch.
  preferences.begin(PREF_NAMESPACE, false);
  historyStorageAvailable = LittleFS.begin(false);
  if (!historyStorageAvailable) {
    Serial.println("Erreur LittleFS ; aucun formatage automatique");
  } else {
    loadHistoryState();
    loadCloudOutboxState();
  }
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
  WiFi.setAutoReconnect(true);
  WiFi.onEvent(handleWifiEvent);
  scanConfiguredWifi();
  connectWifi();
}

void loop() {
  connectWifi();
  if (networkServicesStarted) server.handleClient();

  const unsigned long now = millis();
  if (now - lastSensorRead >= SENSOR_INTERVAL_MS) {
    lastSensorRead = now;
    readSensor();
  }

  if (hasReading && now - lastHistoryWrite >= HISTORY_INTERVAL_MS) {
    lastHistoryWrite = now;
    if (!saveHistoryRecord()) Serial.println("Echec ecriture historique");
  }
  flushCloudOutbox();
}

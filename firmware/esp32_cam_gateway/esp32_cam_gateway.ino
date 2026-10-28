#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>
#include "esp_camera.h"
#include "config.h"

namespace {
constexpr char FIRMWARE_VERSION[] = "cam-gateway-0.1.0";
constexpr uint32_t COMMAND_POLL_INTERVAL_MS = 2000;
constexpr uint32_t HEARTBEAT_INTERVAL_MS = 60000;
constexpr uint32_t PHOTO_COOLDOWN_MS = 10000;
constexpr uint32_t WIFI_TIMEOUT_MS = 20000;
constexpr uint32_t TIME_SYNC_TIMEOUT_MS = 15000;
constexpr uint32_t HTTP_TIMEOUT_MS = 15000;
constexpr size_t MAX_JSON_RESPONSE_BYTES = 8192;
constexpr time_t MIN_VALID_EPOCH = 1704067200;  // 2024-01-01 UTC

// Brochage AI-Thinker ESP32-CAM.
constexpr int PWDN_GPIO_NUM = 32;
constexpr int RESET_GPIO_NUM = -1;
constexpr int XCLK_GPIO_NUM = 0;
constexpr int SIOD_GPIO_NUM = 26;
constexpr int SIOC_GPIO_NUM = 27;
constexpr int Y9_GPIO_NUM = 35;
constexpr int Y8_GPIO_NUM = 34;
constexpr int Y7_GPIO_NUM = 39;
constexpr int Y6_GPIO_NUM = 36;
constexpr int Y5_GPIO_NUM = 21;
constexpr int Y4_GPIO_NUM = 19;
constexpr int Y3_GPIO_NUM = 18;
constexpr int Y2_GPIO_NUM = 5;
constexpr int VSYNC_GPIO_NUM = 25;
constexpr int HREF_GPIO_NUM = 23;
constexpr int PCLK_GPIO_NUM = 22;
constexpr int FLASH_LED_GPIO_NUM = 4;

uint32_t lastPollAt = 0;
uint32_t lastHeartbeatAt = 0;
uint32_t lastPhotoAt = 0;
bool hasCapturedPhoto = false;
uint64_t lastCommandId = 0;

struct HttpResponse {
  int statusCode = 0;
  String body;
};

bool ensureClock() {
  if (time(nullptr) >= MIN_VALID_EPOCH) return true;

  configTime(0, 0, NTP_SERVER_PRIMARY, NTP_SERVER_SECONDARY);
  Serial.print("Synchronisation de l'heure");
  const uint32_t startedAt = millis();
  while (time(nullptr) < MIN_VALID_EPOCH &&
         millis() - startedAt < TIME_SYNC_TIMEOUT_MS) {
    delay(250);
    Serial.print('.');
  }
  Serial.println();

  if (time(nullptr) < MIN_VALID_EPOCH) {
    Serial.println("Heure indisponible : HTTPS bloque par securite");
    return false;
  }
  return true;
}

bool connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return ensureClock();

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connexion au Wi-Fi IoT");
  const uint32_t startedAt = millis();
  while (WiFi.status() != WL_CONNECTED &&
         millis() - startedAt < WIFI_TIMEOUT_MS) {
    delay(500);
    Serial.print('.');
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Echec Wi-Fi");
    return false;
  }
  Serial.println("Wi-Fi connecte");
  return ensureClock();
}

bool connectGateway(WiFiClientSecure& client) {
  if (!connectWifi()) return false;
  client.setCACert(GATEWAY_ROOT_CA);
  client.setTimeout(HTTP_TIMEOUT_MS);
  if (!client.connect(GATEWAY_HOST, GATEWAY_PORT)) {
    Serial.println("Connexion HTTPS au gateway impossible");
    return false;
  }
  return true;
}

bool readHttpResponse(
    WiFiClientSecure& client,
    HttpResponse& response,
    size_t maximumBodyBytes = MAX_JSON_RESPONSE_BYTES) {
  const uint32_t responseStartedAt = millis();
  while (!client.available() && client.connected() &&
         millis() - responseStartedAt < HTTP_TIMEOUT_MS) {
    delay(20);
  }
  if (!client.available()) return false;

  const String statusLine = client.readStringUntil('\n');
  const int firstSpace = statusLine.indexOf(' ');
  response.statusCode =
      firstSpace >= 0 ? statusLine.substring(firstSpace + 1).toInt() : 0;

  int contentLength = -1;
  while (client.connected() || client.available()) {
    String line = client.readStringUntil('\n');
    if (line == "\r" || line.length() == 0) break;
    line.trim();
    if (line.startsWith("Content-Length:")) {
      contentLength = line.substring(15).toInt();
    }
  }
  if (contentLength < 0 || static_cast<size_t>(contentLength) > maximumBodyBytes) {
    return false;
  }

  response.body.reserve(contentLength);
  const uint32_t bodyStartedAt = millis();
  while (response.body.length() < static_cast<size_t>(contentLength) &&
         millis() - bodyStartedAt < HTTP_TIMEOUT_MS) {
    while (client.available() &&
           response.body.length() < static_cast<size_t>(contentLength)) {
      response.body += static_cast<char>(client.read());
    }
    delay(2);
  }
  return response.body.length() == static_cast<size_t>(contentLength);
}

bool sendJsonRequest(
    const char* method,
    const String& path,
    const String& body,
    HttpResponse& response) {
  WiFiClientSecure client;
  if (!connectGateway(client)) return false;

  client.printf("%s %s HTTP/1.1\r\n", method, path.c_str());
  client.printf("Host: %s\r\n", GATEWAY_HOST);
  client.printf("Authorization: Bearer %s\r\n", CAMERA_DEVICE_TOKEN);
  client.println("Accept: application/json");
  client.println("Connection: close");
  if (body.length() > 0) {
    client.println("Content-Type: application/json");
    client.printf("Content-Length: %u\r\n", static_cast<unsigned>(body.length()));
  }
  client.println();
  if (body.length() > 0) client.print(body);

  const bool read = readHttpResponse(client, response);
  client.stop();
  return read;
}

bool initCamera() {
  camera_config_t config{};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (psramFound()) {
    config.frame_size = FRAMESIZE_UXGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
    config.fb_location = CAMERA_FB_IN_DRAM;
  }

  const esp_err_t error = esp_camera_init(&config);
  if (error != ESP_OK) {
    Serial.printf("Echec camera : 0x%x\n", error);
    return false;
  }
  pinMode(FLASH_LED_GPIO_NUM, OUTPUT);
  digitalWrite(FLASH_LED_GPIO_NUM, LOW);
  return true;
}

bool parseUnsignedField(
    const String& json,
    const char* key,
    uint64_t& result) {
  String marker = "\"";
  marker += key;
  marker += "\":";
  const int start = json.indexOf(marker);
  if (start < 0) return false;
  const int valueStart = start + marker.length();
  const char* raw = json.c_str() + valueStart;
  char* end = nullptr;
  const unsigned long long parsed = strtoull(raw, &end, 10);
  if (end == raw) return false;
  result = static_cast<uint64_t>(parsed);
  return true;
}

String unsignedToString(uint64_t value) {
  char buffer[24];
  snprintf(buffer, sizeof(buffer), "%llu", static_cast<unsigned long long>(value));
  return String(buffer);
}

bool uploadPhoto(uint64_t commandId) {
  const uint32_t nowMs = millis();
  if (hasCapturedPhoto && nowMs - lastPhotoAt < PHOTO_COOLDOWN_MS) {
    Serial.println("Capture bloquee par le cooldown local");
    return false;
  }
  hasCapturedPhoto = true;
  lastPhotoAt = nowMs;

  if (CAMERA_FLASH_ENABLED) {
    digitalWrite(FLASH_LED_GPIO_NUM, HIGH);
    delay(150);
  }
  camera_fb_t* frame = esp_camera_fb_get();
  digitalWrite(FLASH_LED_GPIO_NUM, LOW);
  if (!frame) {
    Serial.println("Capture impossible");
    return false;
  }

  WiFiClientSecure client;
  if (!connectGateway(client)) {
    esp_camera_fb_return(frame);
    return false;
  }
  String path = "/internal/v1/cameras/" CAMERA_ID "/snapshots?commandId=";
  path += unsignedToString(commandId);
  client.printf("POST %s HTTP/1.1\r\n", path.c_str());
  client.printf("Host: %s\r\n", GATEWAY_HOST);
  client.printf("Authorization: Bearer %s\r\n", CAMERA_DEVICE_TOKEN);
  client.println("Accept: application/json");
  client.println("Content-Type: image/jpeg");
  client.println("Connection: close");
  client.printf("X-Captured-At: %lld\r\n", static_cast<long long>(time(nullptr)));
  const size_t frameLength = frame->len;
  client.printf("Content-Length: %u\r\n\r\n", static_cast<unsigned>(frameLength));

  size_t sent = 0;
  while (sent < frameLength) {
    const size_t chunk = min(static_cast<size_t>(1024), frameLength - sent);
    const size_t written = client.write(frame->buf + sent, chunk);
    if (written == 0) break;
    sent += written;
  }
  esp_camera_fb_return(frame);
  if (sent == 0 || sent < frameLength) {
    client.stop();
    Serial.println("Upload JPEG incomplet");
    return false;
  }

  HttpResponse response;
  const bool read = readHttpResponse(client, response);
  client.stop();
  const bool accepted = read && response.statusCode == 200 &&
                        (response.body.indexOf("\"status\":\"accepted\"") >= 0 ||
                         response.body.indexOf("\"status\":\"already_accepted\"") >= 0);
  Serial.println(accepted ? "Photo stockee sur le Pi" : "Photo refusee par le Pi");
  return accepted;
}

bool pollCommand() {
  String path = "/internal/v1/cameras/" CAMERA_ID "/commands?after=";
  path += unsignedToString(lastCommandId);
  HttpResponse response;
  if (!sendJsonRequest("GET", path, "", response) || response.statusCode != 200) {
    Serial.println("Lecture des commandes impossible");
    return false;
  }
  if (response.body.indexOf("\"command\":null") >= 0) return true;

  uint64_t commandId = 0;
  uint64_t expiresAt = 0;
  if (!parseUnsignedField(response.body, "id", commandId) ||
      !parseUnsignedField(response.body, "expiresAtEpoch", expiresAt) ||
      commandId <= lastCommandId) {
    Serial.println("Commande gateway invalide");
    return false;
  }
  if (static_cast<uint64_t>(time(nullptr)) >= expiresAt) {
    lastCommandId = commandId;
    Serial.println("Commande expiree ignoree");
    return true;
  }
  if (uploadPhoto(commandId)) {
    lastCommandId = commandId;
    return true;
  }
  return false;
}

bool sendHeartbeat() {
  String body = "{\"firmwareVersion\":\"";
  body += FIRMWARE_VERSION;
  body += "\",\"rssiDbm\":";
  body += WiFi.RSSI();
  body += ",\"freeHeapBytes\":";
  body += ESP.getFreeHeap();
  body += ",\"uptimeSeconds\":";
  body += millis() / 1000;
  body += "}";

  HttpResponse response;
  const bool sent = sendJsonRequest(
      "POST",
      "/internal/v1/cameras/" CAMERA_ID "/heartbeat",
      body,
      response);
  return sent && response.statusCode == 200;
}
}  // namespace

void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!initCamera()) {
    Serial.println("Redemarrage dans 10 secondes");
    delay(10000);
    ESP.restart();
  }

  connectWifi();
  sendHeartbeat();
  lastHeartbeatAt = millis();
  lastPollAt = millis();
}

void loop() {
  const uint32_t now = millis();
  if (now - lastPollAt >= COMMAND_POLL_INTERVAL_MS) {
    lastPollAt = now;
    pollCommand();
  }
  if (now - lastHeartbeatAt >= HEARTBEAT_INTERVAL_MS) {
    lastHeartbeatAt = now;
    if (!sendHeartbeat()) Serial.println("Heartbeat non transmis");
  }
  delay(100);
}

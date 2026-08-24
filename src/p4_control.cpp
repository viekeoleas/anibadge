#include "p4_control.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include "esp_random.h"

#include "p4_web.h"

namespace p4control {
namespace {

constexpr char kDeviceName[] = "Znachok-BMW";
constexpr char kServiceUuid[] = "a1b20000-1111-2222-3333-444455556666";
constexpr char kCommandUuid[] = "a1b20001-1111-2222-3333-444455556666";
constexpr char kResponseUuid[] = "a1b20002-1111-2222-3333-444455556666";
constexpr uint32_t kSessionLifetimeMs = 180000;

enum class PendingCommand : uint8_t { kNone, kPublish, kRelease, kInvalid };

BLEServer *ble_server = nullptr;
BLECharacteristic *response_characteristic = nullptr;
portMUX_TYPE command_mux = portMUX_INITIALIZER_UNLOCKED;
volatile PendingCommand pending_command = PendingCommand::kNone;
char pending_request_id[25] = {};
char session_id[17] = {};
char session_ssid[24] = {};
char session_password[17] = {};

void random_hex(char *output, size_t bytes) {
  static constexpr char kHex[] = "0123456789abcdef";
  for (size_t index = 0; index < bytes; ++index) {
    output[index] = kHex[esp_random() & 0x0f];
  }
  output[bytes] = '\0';
}

void random_password(char *output, size_t bytes) {
  static constexpr char kAlphabet[] =
      "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  constexpr size_t kAlphabetSize = sizeof(kAlphabet) - 1;
  for (size_t index = 0; index < bytes; ++index) {
    output[index] = kAlphabet[esp_random() % kAlphabetSize];
  }
  output[bytes] = '\0';
}

String json_value(const String &source, const char *key) {
  const String marker = String("\"") + key + "\":\"";
  const int start = source.indexOf(marker);
  if (start < 0) return "";
  const int value_start = start + marker.length();
  const int end = source.indexOf('"', value_start);
  if (end < 0) return "";
  return source.substring(value_start, end);
}

void queue_command(PendingCommand command, const String &request_id) {
  portENTER_CRITICAL(&command_mux);
  if (pending_command == PendingCommand::kNone) {
    pending_command = command;
    strlcpy(pending_request_id, request_id.c_str(),
            sizeof(pending_request_id));
  }
  portEXIT_CRITICAL(&command_mux);
}

class CommandCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const String command = characteristic->getValue();
    const String request_id = json_value(command, "id");
    if (command.indexOf("\"v\":1") < 0 || request_id.isEmpty()) {
      queue_command(PendingCommand::kInvalid, request_id);
    } else if (command.indexOf("\"op\":\"publish\"") >= 0) {
      queue_command(PendingCommand::kPublish, request_id);
    } else if (command.indexOf("\"op\":\"release\"") >= 0) {
      queue_command(PendingCommand::kRelease, request_id);
    } else {
      queue_command(PendingCommand::kInvalid, request_id);
    }
  }
};

void notify(const String &response) {
  if (response_characteristic == nullptr) return;
  response_characteristic->setValue(response);
  response_characteristic->notify();
  Serial.printf("BLE CONTROL: %s\n", response.c_str());
}

String response_prefix(const char *operation, const char *request_id) {
  return String("{\"v\":1,\"op\":\"") + operation + "\",\"id\":\"" +
         request_id + "\",";
}

void handle_publish(const char *request_id) {
  if (!p4web::temporary_ap_active()) {
    random_hex(session_id, 16);
    random_password(session_password, 16);
    const uint64_t chip_id = ESP.getEfuseMac();
    snprintf(session_ssid, sizeof(session_ssid), "Znachok-%04X",
             static_cast<unsigned>(chip_id & 0xffff));
    if (!p4web::start_temporary_ap(session_ssid, session_password,
                                   kSessionLifetimeMs)) {
      notify(response_prefix("publish", request_id) +
             "\"ok\":false,\"error\":\"wifi-start\"}");
      return;
    }
  }
  notify(response_prefix("publish", request_id) +
         "\"ok\":true,\"session\":\"" + session_id +
         "\",\"ssid\":\"" + session_ssid + "\",\"password\":\"" +
         session_password +
         "\",\"host\":\"192.168.4.1\",\"ttl\":180}");
}

void handle_release(const char *request_id) {
  p4web::stop_temporary_ap();
  notify(response_prefix("release", request_id) + "\"ok\":true}");
}

}  // namespace

bool begin() {
  if (!BLEDevice::init(kDeviceName)) {
    Serial.println("BLE CONTROL ERROR: initialization failed");
    return false;
  }
  // A publish response carries the temporary Wi-Fi credentials and is larger
  // than the 20-byte payload available with the default ATT MTU.
  if (BLEDevice::setMTU(256) != ESP_OK) {
    Serial.println("BLE CONTROL ERROR: failed to configure MTU");
    return false;
  }
  ble_server = BLEDevice::createServer();
  if (ble_server == nullptr) return false;
  ble_server->advertiseOnDisconnect(true);
  BLEService *service = ble_server->createService(kServiceUuid);
  BLECharacteristic *command = service->createCharacteristic(
      kCommandUuid, BLECharacteristic::PROPERTY_WRITE);
  response_characteristic = service->createCharacteristic(
      kResponseUuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  command->setCallbacks(new CommandCallbacks());
  response_characteristic->setValue(
      "{\"v\":1,\"op\":\"ready\",\"ok\":true}");
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.printf("BLE CONTROL READY: %s, service=%s\n", kDeviceName,
                kServiceUuid);
  return true;
}

void poll() {
  PendingCommand command = PendingCommand::kNone;
  char request_id[sizeof(pending_request_id)] = {};
  portENTER_CRITICAL(&command_mux);
  command = pending_command;
  if (command != PendingCommand::kNone) {
    pending_command = PendingCommand::kNone;
    strlcpy(request_id, pending_request_id, sizeof(request_id));
    pending_request_id[0] = '\0';
  }
  portEXIT_CRITICAL(&command_mux);

  switch (command) {
    case PendingCommand::kPublish:
      handle_publish(request_id);
      break;
    case PendingCommand::kRelease:
      handle_release(request_id);
      break;
    case PendingCommand::kInvalid:
      notify(response_prefix("error", request_id) +
             "\"ok\":false,\"error\":\"invalid-command\"}");
      break;
    case PendingCommand::kNone:
      break;
  }
}

}  // namespace p4control

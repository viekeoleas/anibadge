#include "p4_web.h"

#include <Arduino.h>
#include <WebServer.h>
#include <WiFi.h>

#include "p4_runtime.h"
#include "p4_show_player.h"
#include "p4_storage.h"
#include "p4_upload_ui.h"

namespace p4web {
namespace {

WebServer server(80);
bool upload_ok = false;
bool show_upload_error_visible = false;
bool ap_active = false;
bool upload_in_progress = false;
uint32_t ap_deadline_ms = 0;
uint32_t ap_lifetime_ms = 0;
enum class UploadKind : uint8_t { kGif, kShow };
UploadKind upload_kind = UploadKind::kGif;
size_t upload_expected = 0;
size_t upload_received = 0;
uint8_t shown_percent = 255;
uint32_t upload_start_ms = 0;

void extend_ap_deadline() {
  if (ap_active) ap_deadline_ms = millis() + ap_lifetime_ms;
}

void update_upload_progress() {
  if (upload_expected == 0) return;
  uint64_t calculated =
      (static_cast<uint64_t>(upload_received) * 100U) / upload_expected;
  if (calculated > 100) calculated = 100;
  const uint8_t percent = static_cast<uint8_t>(calculated);
  // A full 800x800 refresh is intentionally limited to 2% steps so display
  // updates do not throttle the HTTP transfer.
  if (percent == 100 || shown_percent == 255 || percent >= shown_percent + 2) {
    shown_percent = percent;
    if (upload_kind == UploadKind::kShow) {
      p4uploadui::show_show_progress(percent);
    } else {
      p4uploadui::show_progress(percent);
    }
  }
}

void receive_upload(UploadKind kind) {
  HTTPUpload &upload = server.upload();
  if (upload.status == UPLOAD_FILE_START) {
    upload_in_progress = true;
    extend_ap_deadline();
    upload_kind = kind;
    if (kind == UploadKind::kShow) show_upload_error_visible = false;
    upload_expected = static_cast<size_t>(
        strtoull(server.arg("size").c_str(), nullptr, 10));
    upload_received = 0;
    shown_percent = 255;
    upload_start_ms = millis();
    // The decoder owns the screen from another task. Stop it before rendering
    // upload status so the GIF and progress screen cannot alternate/flicker.
    p4runtime::stop();
    upload_ok = kind == UploadKind::kShow
                    ? p4storage::begin_show_stream_upload(
                          server.arg("name").c_str(), upload_expected)
                    : p4storage::begin_stream_upload(
                          server.arg("name").c_str(), upload_expected);
    Serial.printf("HTTP %s: begin %u bytes\n",
                  kind == UploadKind::kShow ? "SHOW" : "GIF",
                  static_cast<unsigned>(upload_expected));
    if (upload_ok) {
      update_upload_progress();
    } else {
      if (upload_kind == UploadKind::kShow) show_upload_error_visible = true;
      p4uploadui::show_error();
    }
  } else if (upload.status == UPLOAD_FILE_WRITE) {
    extend_ap_deadline();
    if (upload_ok) {
      upload_ok = p4storage::write_stream_upload(upload.buf, upload.currentSize);
      if (upload_ok) {
        upload_received += upload.currentSize;
        update_upload_progress();
      } else {
        if (upload_kind == UploadKind::kShow) show_upload_error_visible = true;
        p4uploadui::show_error();
      }
    }
  } else if (upload.status == UPLOAD_FILE_END) {
    upload_in_progress = false;
    extend_ap_deadline();
    const uint32_t transfer_ms = millis() - upload_start_ms;
    Serial.printf("HTTP %s: transfer %u bytes in %u ms (%.1f KB/s)\n",
                  upload_kind == UploadKind::kShow ? "SHOW" : "GIF",
                  static_cast<unsigned>(upload_received),
                  static_cast<unsigned>(transfer_ms),
                  transfer_ms > 0
                      ? upload_received / 1.024 / transfer_ms
                      : 0.0);
    if (upload_ok) {
      upload_ok = upload_kind == UploadKind::kShow
                      ? p4storage::finish_show_stream_upload()
                      : p4storage::finish_stream_upload();
      if (upload_ok) {
        upload_received = upload_expected;
        update_upload_progress();
        if (upload_kind == UploadKind::kShow) {
          p4uploadui::show_show_complete();
        } else {
          p4uploadui::show_complete();
        }
      } else {
        if (upload_kind == UploadKind::kShow) show_upload_error_visible = true;
        p4uploadui::show_error();
      }
    } else {
      p4storage::abort_stream_upload();
      if (upload_kind == UploadKind::kShow) show_upload_error_visible = true;
      p4uploadui::show_error();
    }
  } else if (upload.status == UPLOAD_FILE_ABORTED) {
    upload_in_progress = false;
    p4storage::abort_stream_upload();
    upload_ok = false;
    if (upload_kind == UploadKind::kShow) show_upload_error_visible = true;
    p4uploadui::show_error();
  }
}

void receive_gif_upload() { receive_upload(UploadKind::kGif); }

void receive_show_upload() { receive_upload(UploadKind::kShow); }

void finish_upload_request() {
  if (upload_kind == UploadKind::kShow) {
    const String body = upload_ok
                            ? "{\"ok\":true,\"validation\":\"ok\","
                              "\"installed\":true}"
                            : String("{\"ok\":false,\"error\":\"") +
                                  p4storage::last_show_upload_error() + "\"}";
    server.send(upload_ok ? 200 : 422, "application/json", body);
  } else {
    server.send(upload_ok ? 200 : 422, "application/json",
                upload_ok ? "{\"ok\":true}" : "{\"ok\":false}");
  }
  upload_ok = false;
  upload_expected = 0;
  upload_received = 0;
}

void show_status_request() {
  const bool installed = p4storage::show_exists();
  const char *state = "idle";
  if (p4runtime::show_running()) {
    state = "playing";
  } else if (show_upload_error_visible) {
    state = "error";
  } else if (p4runtime::fallback_active()) {
    state = "fallback";
  } else if (installed) {
    state = "installed";
  }
  const String body = String("{\"state\":\"") + state +
                      "\",\"installed\":" +
                      (installed ? "true" : "false") +
                      ",\"playerVersion\":\"2.2.0\",\"frame\":" +
                      p4showplayer::current_frame_index() +
                      ",\"frames\":" + p4showplayer::frame_count() +
                      ",\"cycles\":" + p4showplayer::completed_cycles() +
                      ",\"decodeErrors\":" +
                      p4showplayer::decode_error_count() + "}";
  server.send(200, "application/json", body);
}

void clear_media_request() {
  p4runtime::stop();
  const bool cleared = p4storage::clear_media();
  show_upload_error_visible = false;
  p4runtime::play_startup_media();
  server.send(cleared ? 200 : 500, "application/json",
              cleared ? "{\"ok\":true,\"installed\":false}"
                      : "{\"ok\":false,\"error\":\"clear-failed\"}");
}

}  // namespace

bool begin() {
  server.on("/health", HTTP_GET,
            []() { server.send(200, "text/plain", "OK"); });
  server.on(
      "/upload", HTTP_POST,
      finish_upload_request, receive_gif_upload);
  server.on("/show/upload", HTTP_POST, finish_upload_request,
            receive_show_upload);
  server.on("/show/status", HTTP_GET, show_status_request);
  server.on("/show/clear", HTTP_POST, clear_media_request);
  server.onNotFound(
      []() { server.send(404, "application/json", "{\"ok\":false}"); });
  Serial.println("WIFI READY: waiting for BLE publish session");
  return true;
}

bool start_temporary_ap(const char *ssid, const char *password,
                        uint32_t lifetime_ms) {
  if (ssid == nullptr || password == nullptr || strlen(password) < 8 ||
      lifetime_ms < 10000) {
    return false;
  }
  if (ap_active) stop_temporary_ap();
  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(ssid, password)) {
    WiFi.mode(WIFI_OFF);
    return false;
  }
  server.begin();
  ap_active = true;
  upload_in_progress = false;
  ap_lifetime_ms = lifetime_ms;
  extend_ap_deadline();
  Serial.printf("WIFI SESSION: %s, http://%s/, ttl=%u ms\n", ssid,
                WiFi.softAPIP().toString().c_str(),
                static_cast<unsigned>(lifetime_ms));
  return true;
}

void stop_temporary_ap() {
  if (!ap_active) return;
  server.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  ap_active = false;
  upload_in_progress = false;
  ap_deadline_ms = 0;
  ap_lifetime_ms = 0;
  Serial.println("WIFI SESSION: closed");
}

bool temporary_ap_active() { return ap_active; }

void poll() {
  if (!ap_active) return;
  server.handleClient();
  if (!upload_in_progress &&
      static_cast<int32_t>(millis() - ap_deadline_ms) >= 0) {
    Serial.println("WIFI SESSION: expired");
    stop_temporary_ap();
  }
}

}  // namespace p4web

#pragma once

#include <stdint.h>

namespace p4web {

bool begin();
void poll();
bool start_temporary_ap(const char *ssid, const char *password,
                        uint32_t lifetime_ms);
void stop_temporary_ap();
bool temporary_ap_active();

}  // namespace p4web

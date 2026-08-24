# BLE publish control v1

The ESP32-P4 advertises the primary service
`a1b20000-1111-2222-3333-444455556666` under the name `Znachok-BMW`.
BLE is the discovery and control plane only; ZSHOW bytes continue to use HTTP
over a temporary Wi-Fi access point.

## Characteristics

- Command, write: `a1b20001-1111-2222-3333-444455556666`
- Response, read/notify: `a1b20002-1111-2222-3333-444455556666`

Every message is a UTF-8 JSON object with protocol version, operation and a
caller-generated correlation ID. Unknown versions and operations fail closed.
Future pairing can add an `auth` member without changing the publish operation
or the HTTP package contract.

Open a session:

```json
{"v":1,"op":"publish","id":"94b6c1a580de4f71"}
```

Successful response:

```json
{"v":1,"op":"publish","id":"94b6c1a580de4f71","ok":true,"session":"934a4a7e8813f019","ssid":"Znachok-D24F","password":"temporary-pass","host":"192.168.4.1","ttl":180}
```

The SSID identifies the board; password and session ID are regenerated after
boot or when a new session starts. The access point expires after 180 seconds
of inactivity. Active upload chunks extend the deadline.

Release a session:

```json
{"v":1,"op":"release","id":"6247d97ea75041fd"}
```

The firmware stops the HTTP server and Wi-Fi AP before acknowledging the
release. BLE remains available and advertising restarts after disconnect.

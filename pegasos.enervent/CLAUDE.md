# Enervent Pegasos Eco ECE → Home Assistant (ESPHome) Integration Notes

> **Technical reference: current state and reasoning.** Overview: [README.md](README.md).

## Goal

Integrate an Enervent Pegasos Eco ECE ventilation unit with Home Assistant using a local ESPHome bridge over RS-485/Modbus.

## Current Environment

- Home Assistant running in Podman
- Enervent Pegasos Eco ECE ventilation unit
- RJ11 service connector available
- Suspected communication protocol: RS-485 (Modbus RTU)

## Hardware

### Required

- ESP32 development board (recommended over ESP8266)
- MAX485 (or equivalent) RS485 ↔ TTL transceiver
- RJ11 cable

### Optional

- RJ11 breakout adapter (not required if you are willing to cut one end of an RJ11 cable)

## Why ESP32 instead of ESP8266?

Although an ESP8266 can technically communicate over Modbus, the ESP32 is the better choice because it offers:

- Multiple hardware UARTs
- Better ESPHome support
- Easier debugging while Modbus is running
- More reliable long-term serial communication
- Better expandability for future sensors or controls

ESP8266 is usable but requires disabling the serial logger and has fewer resources.

## Architecture

```
Enervent Pegasos Eco ECE
        │
      RJ11
        │
   RS-485 (A/B)
        │
     MAX485 module
        │
      UART (TTL)
        │
       ESP32
        │
      Wi-Fi API
        │
 Home Assistant (Podman)
```

## ESP32 ↔ MAX485 Wiring

Typical wiring:

| MAX485 | ESP32 |
|--------|-------|
| RO | RX (GPIO16) |
| DI | TX (GPIO17) |
| RE + DE | GPIO4 |
| VCC | 3.3 V |
| GND | GND |

## MAX485 ↔ Enervent

The MAX485 connects to the Enervent RS-485 bus.

```
Enervent A (D+)
        │
        ├──── MAX485 A

Enervent B (D-)
        │
        ├──── MAX485 B
```

If communication fails initially, swap A and B.

## RJ11 Notes

The Enervent uses an RJ11 connector rather than screw terminals.

An RJ11 breakout board is **not required** if:

- a normal RJ11 cable is used
- one end of the cable is cut
- the conductors are stripped and connected directly to the MAX485

A breakout adapter is only recommended because it makes identifying the correct pins easier.

## Important Warning

Do **not** assume the RJ11 pinout.

The connector may contain:

- RS-485 A/B
- Ground
- Supply voltage

The pinout should be verified before wiring.

## ESPHome

Recommended communication settings:

- Protocol: Modbus RTU
- Baud rate: 9600
- Data bits: 8
- Parity: None
- Stop bits: 1

Typical slave ID is 1 but should be verified.

ESPHome components:

- uart
- modbus
- modbus_controller

## Home Assistant

No USB passthrough is required because the ESP32 communicates with Home Assistant over Wi-Fi using the native ESPHome API.

Advantages:

- No serial devices inside the Podman container
- Automatic entity discovery
- OTA firmware updates
- Stable long-term operation

## Remaining Unknowns

The following information still needs to be determined:

1. RJ11 pinout
2. Modbus slave address
3. Enervent Modbus register map

Once the register map is available, ESPHome can expose:

- Supply air temperature
- Extract air temperature
- Outdoor air temperature
- Exhaust air temperature
- Fan speeds
- Operating mode
- Boost mode
- Filter reminder
- Alarm status
- Heat recovery status

## Next Steps

1. Obtain or identify the RJ11 pinout.
2. Connect the MAX485 to the ESP32.
3. Flash ESPHome onto the ESP32.
4. Verify Modbus communication.
5. Identify the correct Modbus registers.
6. Add sensors, switches and controls in ESPHome.
7. Integrate with Home Assistant.

## Long-Term Goal

Create a completely local integration for the Enervent Pegasos Eco ECE that provides monitoring and control through Home Assistant without relying on any cloud service.

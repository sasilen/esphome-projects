# Enervent Pegasos Eco ECE → Home Assistant

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

Local monitoring and control of an Enervent Pegasos Eco ECE ventilation unit over
RS-485/Modbus RTU, bridged to Home Assistant by an ESP32 running ESPHome. No cloud
service, no MQTT — the ESPHome native API only.

**Status: planning.** Nothing is wired yet, and three prerequisites are still
unknown (see below).

## Architecture

```
Enervent Pegasos Eco ECE
        │  RJ11 service connector
        │  RS-485 (A/B)
        ▼
   MAX485 module
        │  UART (TTL)
        ▼
       ESP32
        │  ESPHome native API over Wi-Fi
        ▼
 Home Assistant (Podman)
```

Because the ESP32 talks to Home Assistant over Wi-Fi, no USB passthrough into the
Podman container is needed — no serial devices inside the container, automatic
entity discovery, and OTA firmware updates.

## Hardware

**Required**

- ESP32 development board — in stock, see [`CLAUDE.md`](CLAUDE.md)
- RS-485 ↔ TTL module — in stock, JZK with automatic direction control, 5 pcs
- RJ11 cable — **not in stock**

**Optional**

- RJ11 breakout adapter — not required if you are willing to cut one end off an
  RJ11 cable, strip the conductors and wire them straight to the MAX485. The
  breakout only makes identifying the pins easier.

### Why ESP32 rather than ESP8266

An ESP8266 can do Modbus, but it has to give up its serial logger to do it. The
ESP32 has multiple hardware UARTs, which keeps debugging possible *while* Modbus
is running — plus more headroom for future sensors.

## Wiring

| RS-485 module | ESP32 |
|---|---|
| RXD | TX (GPIO17) |
| TXD | RX (GPIO16) |
| VCC | 3.3 V |
| GND | GND |

Four wires, not five: the boards in stock switch direction in hardware, so there
is no DE/RE pin to drive and no `flow_control_pin` in the YAML. If the board you
pick up does expose DE and RE, it is the older MAX485 type — see
[`CLAUDE.md`](CLAUDE.md).

Module A → Enervent A (D+), module B → Enervent B (D−). If communication fails on
the first try, swap A and B — this is the cheapest thing to rule out.

> **Do not assume the RJ11 pinout.** The connector may carry RS-485 A/B, ground
> *and a supply voltage*. Measure before wiring anything.

## Modbus settings

Starting point, all to be verified against the unit:

| Setting | Value |
|---|---|
| Protocol | Modbus RTU |
| Baud rate | 9600 |
| Frame | 8N1 |
| Slave ID | 1 (typical — verify) |

ESPHome components: `uart`, `modbus`, `modbus_controller`.

## Remaining unknowns

Three things block the build, in this order:

1. **RJ11 pinout** — must be measured, not assumed
2. **Modbus slave address**
3. **Enervent Modbus register map**

Once the register map is known, ESPHome can expose supply / extract / outdoor /
exhaust air temperatures, fan speeds, operating mode, boost mode, filter reminder,
alarm status and heat recovery status.

## Next steps

1. Obtain or identify the RJ11 pinout
2. Connect the MAX485 to the ESP32
3. Flash ESPHome onto the ESP32
4. Verify Modbus communication
5. Identify the correct Modbus registers
6. Add sensors, switches and controls in ESPHome
7. Integrate with Home Assistant

Full notes: [`CLAUDE.md`](CLAUDE.md).

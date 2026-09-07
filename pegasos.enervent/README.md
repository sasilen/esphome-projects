# Enervent Pegasos Eco ECE → Home Assistant

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

Local monitoring and control of an Enervent Pegasos Eco ECE ventilation unit over
RS-485/Modbus RTU, bridged to Home Assistant by an ESP32 running ESPHome. No cloud
service, no MQTT — the ESPHome native API only.

**Status: planning, waiting on one cable.** Nothing is wired yet. The three
prerequisites that used to be unknown now have documented sources, so what is
left is verifying them on this unit — and getting a **4P4C** cable, which is the
only item with a delivery time behind it.

## Architecture

```
Enervent Pegasos Eco ECE
        │  4P4C service connector (Freeway port)
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
- **4P4C cable** (also sold as RJ10, or as a telephone handset cord) — **not in
  stock.** Not RJ11: a six-position plug does not fit a four-position jack, and
  this file said RJ11 until the connector was looked at

**Optional**

- A breakout adapter — not required if you are willing to cut one end off the
  cable, strip the conductors and wire them straight to the module. It only
  makes identifying the pins easier, and an RJ11 breakout will not fit.

### Why ESP32 rather than ESP8266

**Not because an ESP8266 could not do it** — it could. One of the DevKit pair is
already allocated here, while the spare D1 mini is the fallback for the one
system in this repo that is running. Reasoning, and the three-line path back to
an ESP8266 if a board is ever needed elsewhere: [`CLAUDE.md`](CLAUDE.md).

## Wiring

Drawn out in [`wiring.svg`](wiring.svg).

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

On the Enervent side, red → A, green → B, yellow → ground.

> **Pin 1 is +5 V. Leave it unconnected.** Find the supply pin with a meter
> before wiring anything, and do not trust pin numbers through the cable —
> handset cords are reversed end to end. Reasoning in [`CLAUDE.md`](CLAUDE.md).

## Modbus settings

Starting point, all to be verified against the unit:

| Setting | Value |
|---|---|
| Protocol | Modbus RTU |
| Baud rate | 9600 (19200 is the other candidate) |
| Frame | 8N1 |
| Slave ID | read it from the control panel — **and change 0 to 1** |

ESPHome components: `uart`, `modbus`, `modbus_controller`.

## What is left

Not research any more — verification, plus one purchase:

1. **A 4P4C cable in hand.** The only item with a delivery time
2. **Count the positions in the jack** before ordering — four or six
3. **The pinout, on a meter.** The documented one is from a project that
   confirms Pingvin, Pandion, Pelican and LTR-3 — not Pegasos
4. **The slave address**, from the control panel
5. **The register map**, against Enervent's own *Modbus Registers* document,
   linked in [`CLAUDE.md`](CLAUDE.md)

Once the registers are known, ESPHome can expose supply / extract / outdoor /
exhaust air temperatures, fan speeds, operating mode, boost mode, filter reminder,
alarm status and heat recovery status.

## Next steps

1. Count the connector positions
2. Read the Modbus address from the panel, change it to 1 if it reads 0
3. Get the cable, cut one end, identify the conductors by colour and confirm
   with a meter
4. Wire the module to the ESP32 and to A/B/ground — black to nothing
5. Flash ESPHome and send one read request; if nothing answers, swap A and B,
   then try 19200
6. Identify the registers, then add sensors, switches and controls
7. Integrate with Home Assistant

Full notes: [`CLAUDE.md`](CLAUDE.md).

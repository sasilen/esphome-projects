# Stiebel Eltron WPC 07 → Home Assistant (CAN bus, without MQTT)

> **Technical details and reasoning.** Overview: [README.md](README.md).

## Goal

Connect a Stiebel Eltron WPC 07 heat pump directly to Home Assistant using CAN bus and ESPHome, **without MQTT**.

## What already exists

Blunt on/off control is already in place. The **EVU blocking contact is wired and
in use**: 230 V, switched by a Shelly relay, exposed in Home Assistant as a switch
entity ("MLP EVU"). That is SG Ready states 1 (block) and 2 (normal) — one bit,
and it can only ever take load *away*.

Polarity: **relay ON = pump runs, OFF = blocked.** The HA switch therefore means
"permitted to run", not "block engaged" — worth remembering before writing any
automation against it.

## Scope

This project covers **both directions**: reading the operating data, and writing
the parameters the WPM exposes on the bus.

The target is **heating curve control from Home Assistant**. Raising the curve —
or the room and DHW setpoints — when there is solar surplus stores energy in the
building mass and the tank. That is a better instrument than SG Ready's "force
on": it is proportional, and it works with the heat pump's own logic instead of
overriding it.

Writing here is not blind reverse engineering. The FEK/FE7 room controller and the
ISG already write setpoints over this same bus, so mirroring elements an existing
participant writes is a much smaller step than inventing traffic.

Together with the Shelly, the control set becomes:

| Instrument | Type | Use |
|---|---|---|
| EVU contact (Shelly) | one bit, hard | peak shaving, hard block on expensive hours |
| CAN parameter writes | continuous | curve and setpoint shifting, solar surplus |
| CAN reads | feedback | closes the loop on both of the above |

---

# Existing Hardware

## Available

- **ESP32, several boards** — chosen MCU. The one measured is ESP32-D0WD-V3 rev v3.1.
- ESP8266 Wemos D1 Mini (NodeMCU) — works equally well, fallback
- MCP2515 CAN bus modules with TJA1050 transceiver (3 pcs)
- Dupont jumper wires
- Various resistors (including 120 Ω — not used, see Wiring)

## MCU choice

ESP32, but the margin over the ESP8266 is thin — take one because several are
already in the box, not because it is required.

The only real advantage left is **RAM headroom**. Stiebel's element lists run to
hundreds of parameters; if 50–100 of them end up as HA entities the ESP8266 gets
tight. For a dozen entities the ESP8266 is entirely sufficient.

**No external antenna needed.** The heat pump is in a technical room with good
WiFi, not in a metal cabinet — the WROOM-32U / u.FL argument that applies to the
Aidon install does not apply here. Only re-check if the board ends up inside the
pump's own casing rather than beside it.

The ESP32 does **not** avoid the level-shifting work. It is a 3.3 V part like the
ESP8266, so the MCP2515 module needs the same modification either way.

## Not Used

The following components are **not needed** for this project:

- CC1101 868 MHz radio module
- 868 MHz antennas
- SN65HVD230 (belonged to the rejected esp32_can route)

---

# Additional Hardware Needed

## 1. Connection to the CAN bus

Depending on the WPC installation, one of the following is needed:

### Option A (preferred)

Access the CAN bus directly from the heat pump control board.

Required signals:

- CAN_H
- CAN_L
- GND

### Option B

Use the service RJ12 connector if the CAN bus is exposed there.

In that case you'll need:

- RJ12 (6P6C) cable
- or an RJ12 breakout adapter

The RJ12 cable is **not required** if connecting directly to the control board.

---

## 2. Power Supply

One of the following:

- USB power supply for the ESP8266
- 5 V power supply
- LM2596 step-down converter if powering from the heat pump

---

## 3. Transceiver — Adafruit CAN Pal (#5708)

**One part, useful in both branches.** TJA1051T/3 breakout with two properties that
matter here:

- **Integrated 5 V generator** — makes the transceiver's 5 V from 3.3 V on board.
  The entire two-rail problem disappears: feed it 3.3 V and nothing else.
- **Switchable termination** — 60 Ω + 60 Ω split, 120 Ω across the bus.
  **Switch it OFF.** This node taps an already-terminated bus. Single most
  important setting on the board.
- 3.5 mm terminal block for CANH / CANL / GND.
- Logic level 3.3–5 V, so it accepts the MCP2515 running at 3.3 V directly.

This supersedes the earlier plan of swapping a bare TJA1051T/3 onto the module.
No bare chips, no two-rail modification, no 100 nF work.

TVS (PESD1CAN / NUP2105L) is still worth adding unless the CAN Pal already carries
bus protection — the cabinet switches inductive loads and that couples in. Check
the board first.

---

# Wiring

## Critical: the module is a 5 V design, the ESP8266 is 3.3 V

The common "MCP2515 + TJA1050" module is built as a 5 V board because the
**TJA1050 transceiver requires 4.75–5.25 V**. Powering the module from 5 V and
wiring SPI straight to a D1 Mini is wrong in both directions:

| Direction | Problem |
|-----------|---------|
| MCP2515 → ESP | SO and INT drive 0/5 V. The ESP8266 GPIO absolute maximum is 3.6 V. |
| ESP → MCP2515 | At VDD = 5 V the MCP2515 input threshold is VIH = 0.7 × VDD = **3.5 V**. A 3.3 V output is below spec (often works on the bench, not dependable). |

The MCP2515 itself runs on 2.7–5.5 V, so the fix is to **split the module across
two rails**: controller on 3.3 V, transceiver on 5 V. SPI is then entirely 3.3 V
and no level shifter is needed anywhere.

**The chosen solution avoids all of this: run the module entirely at 3.3 V and
bypass its transceiver with the CAN Pal.**

- Module VCC → 3.3 V. MCP2515 is in spec (2.7–5.5 V) and SPI is safe for the ESP32.
- The on-board TJA1050 ends up under-volted and unused. Its CANH/CANL terminals and
  its 120 Ω stay unconnected, so **neither needs removing.**
- **Lift MCP2515 pin 2 (RXCAN)** and wire it to the CAN Pal's RX. This is the only
  mandatory rework — without it the on-board TJA1050's RXD output and the CAN Pal's
  RX output fight over the same node.
- **MCP2515 pin 1 (TXCAN) → CAN Pal TX.** Can be tapped on the existing net; the
  TJA1050's TXD is a high-impedance input and does not interfere.

Lifting one SOIC-18 pin is less work than swapping an SO8 chip, and needs no hot
air. Having three modules still helps: one is allowed to die.

Superseded plan (kept for reasoning): the two-rail modification — cut MCP2515 VDD
from the 5 V rail, replace TJA1050 with TJA1051T/3, VIO to 3.3 V. Correct, but the
CAN Pal's on-board 5 V generator makes it unnecessary.

---

## ESP8266 (Wemos D1 Mini) ↔ MCP2515 (after modification)

| MCP2515 module | Wemos D1 Mini | Note |
|----------------|---------------|------|
| MCP2515 VDD (pin 18) | 3V3 | after cutting it from the 5 V rail |
| transceiver VCC (module VCC pin) | 5V | |
| TJA1051T/3 pin 5 (VIO) | 3V3 | |
| GND | G | |
| CS | D8 (GPIO15) | |
| SCK | D5 (GPIO14) | |
| SI (MOSI) | D7 (GPIO13) | |
| SO (MISO) | D6 (GPIO12) | |
| INT | D1 (GPIO5) | |

If the board fails to boot, move CS off D8 — GPIO15 must be low at boot.

---

## MCP2515 ↔ Heat Pump

| MCP2515 | Heat Pump |
|----------|-----------|
| CANH | CAN_H |
| CANL | CAN_L |
| GND | GND |

**Remove the module's on-board 120 Ω terminator** (usually soldered on, sometimes
on a jumper). The Stiebel bus is already terminated at both ends; a third 120 Ω
drops the impedance to roughly 60 Ω and can break the heat pump's own traffic.
The loose 120 Ω resistor in the parts box stays in the box — this node is a tap,
not a bus end.

Twisted pair for CANH/CANL. At 20 kbps the bus tolerates hundreds of metres and
long stubs, so cable lengths are not a concern here.

---

## Grounding and power

This is what decides reliability in a permanent install. If the Stiebel connector
carries a supply voltage (the FE7/FEK room-controller bus normally does), **take
the ESP's power from there via the LM2596**. That gives a single ground reference
and no ground loop. An ESP powered from a laptop USB port while connected to the
heat pump bus is exactly the arrangement where loop currents run through the CAN
conductors.

Measure the connector voltages before connecting anything, and do not feed bus
supply voltage into the transceiver.

---

# CAN Bus Settings

Expected configuration for Stiebel Eltron WPC series:

- Bitrate: **20 kbps** (expected, not yet measured)
- CAN 2.0B
- Listen-only mode initially — see below
- 120 Ω termination only if located at the end of the CAN bus (this node is not)

## Check the crystal

These modules ship with either an 8 MHz or a 16 MHz crystal. ESPHome defaults to
8 MHz, so a 16 MHz module with no `clock:` line gets the bit rate wrong by a
factor of two and nothing works. Read the marking on the can.

## Why listen-only actually matters

A CAN node in normal mode **acknowledges frames and emits error frames** even if
it never sends a message of its own. With the wrong bit rate it will actively
disturb the heat pump's bus. Listen-only is fully passive.

Check whether the installed ESPHome version exposes listen-only on the mcp2515
component. If it does not, verify the bit rate independently (logic analyser or
scope) before connecting, rather than trusting the 20 kbps assumption.

## Phase 1: sniffing before the final circuit

The bit rate can be confirmed before buying anything by running **the whole module
on 3.3 V**. The MCP2515 is then within spec, the ESP is safe, and the TJA1050
receiver works in practice even under-volted. The only thing that does not work is
driving the dominant bit — which is precisely what listening does not need.

**Two things must be handled for this test:**

1. **Remove the module's 120 Ω.** In this test the module's *own* transceiver and
   terminals are in use, so its terminator sits across the live bus. Three
   terminators give ~40 Ω, below what the transceivers are specified to drive, and
   that can disturb the heat pump's own traffic. (In the final CAN Pal wiring the
   module's bus side is unused and the resistor can stay.)

2. **Enforce listen-only in hardware.** ESPHome's mcp2515 component may not expose
   listen-only mode. Rather than depend on it, **lift the TJA1050's pin 1 (TXD) and
   tie it to the module's VCC** (TXD high = recessive). The node then physically
   cannot drive the bus: no ACK, no error frames, whatever bit rate is configured.

   Dedicate one of the three modules as the permanent sniffer this way. The MCP2515
   will go error-passive because its transmissions are never acknowledged — that is
   internal to the chip and never reaches the bus.

With TXD lifted, sweeping bit rates is risk-free. Try 20 → 25 → 50 kbps until
frames appear.

---

# ESPHome Configuration (starting point)

```yaml
esphome:
  name: wpc_can

esp8266:
  board: d1_mini

wifi:
  ssid: "YOUR_WIFI"
  password: "YOUR_PASSWORD"

logger:

api:

ota:

spi:
  clk_pin: D5
  mosi_pin: D7
  miso_pin: D6

canbus:
  - platform: mcp2515
    id: can0
    cs_pin: D8
    clock: 16MHZ      # or 8MHZ — must match the module's crystal
    can_id: 0x680
    bit_rate: 20kbps
```

---

# Home Assistant Integration

Communication uses:

```
ESPHome API
```

No MQTT broker is required.

---

# Remaining Tasks

## Phase 1 — read

- Locate CAN_H, CAN_L and GND on the WPC 07.
- Verify the CAN bitrate (expected 20 kbps) — stay listen-only until confirmed.
- Capture CAN frames.
- Map frame IDs against the published element lists.
- Create ESPHome sensors.
- Expose entities directly to Home Assistant.

## Phase 2 — write

- **Build a two-node bench bus first.** Two modified modules, 120 Ω at each end,
  nothing connected to the heat pump. Prove you can send a frame and that the
  other node receives it *before* joining a live system as an active participant.
  A wrong bit rate or a transceiver stuck in standby is harmless on the bench and
  is not harmless on the heat pump's bus. This is the only place the 120 Ω
  resistors get used.
- Identify the writable elements: heating curve slope, room setpoint
  (comfort/ECO), DHW setpoint, operating mode.
- Give the node a bus identity. Writing means leaving listen-only, so the bit rate
  has to be confirmed first and the node must address the WPM the way an FEK or
  ISG does.
- **Rate-limit the writes.** If the WPM persists these parameters, writing every
  few seconds is an EEPROM wear problem. Write on change only, with a deadband and
  a minimum interval.
- **Make the offset self-clearing.** If HA dies while the curve is raised, the
  house overheats and the surplus optimisation turns into a cost. The write path
  needs the same watchdog thinking as the Shelly's Auto-ON timer: the baseline has
  to come back without HA being alive to restore it.

---

# Hardware Summary

## Already Available

- ✅ ESP8266 Wemos D1 Mini
- ✅ MCP2515 + TJA1050
- ✅ Dupont wires
- ✅ 120 Ω resistor (not needed — this node taps an already-terminated bus)

## Still Needed

- **Adafruit CAN Pal #5708** (TJA1051T/3 breakout) × 1
- PESD1CAN or NUP2105L (SOT-23) — only if the CAN Pal has no bus protection
- LM2596 or similar buck, if power is taken from the heat pump

Do **not** order until the bit rate is measured — it decides whether the MCP2515 is
needed at all (see Notes). The CAN Pal is useful either way; nothing else is.

## Optional

- RJ12 cable (only if using service connector)
- RJ12 breakout board
- LM2596 step-down converter (preferred once confirmed the bus connector carries supply voltage)
- Enclosure

---

# Notes

The CC1101 radio modules and 868 MHz antennas are unrelated to the CAN bus interface and are not used in this project.

ESP32 would provide more processing power, but the ESP8266 is sufficient for CAN bus monitoring via MCP2515.

## Rejected: ESP32 built-in CAN (esp32_can) — tested, does not work

The ESP32's built-in TWAI controller would have dropped the MCP2515, the SPI
wiring and the level-shifting problem in one go. It cannot be used here.

ESPHome 2026.7.4 refuses the bit rate outright:

    canbus.esp32_can: [source /config/cantest.yaml:7]
      Bit rate 20KBPS is not supported on ESP32.

Note the distinction: **this is an ESPHome limit, not a silicon limit.** The board
on hand is an ESP32-D0WD-V3 **revision v3.1**, whose BRP divider reaches 20 kbps
without trouble (rev 2+ suffices). ESPHome's `esp32_can` component simply does not
expose rates below 25 kbps.

The option therefore reopens if ESPHome ever adds them. Until then: MCP2515, which
does 20 kbps unconditionally.

Consequence: **no SN65HVD230 needed** — that part belonged to this route only, and
the SMD rework on the MCP2515 module is unavoidable.

Cheap way to re-test after an ESPHome upgrade — needs no hardware, just validation:

    podman exec esphome esphome config /config/cantest.yaml

The preferred architecture is:

```
Stiebel WPC 07
        │
     CAN Bus
        │
    MCP2515/TJA1050
        │
   ESP8266 (ESPHome)
        │
 ESPHome Native API
        │
 Home Assistant
```

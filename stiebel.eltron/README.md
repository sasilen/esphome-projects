# Stiebel Eltron WPC 07 → Home Assistant (CAN bus)

Read the heat pump's operating data over its CAN bus and — in phase 2 — write the
parameters the WPM exposes, straight from Home Assistant via ESPHome. No MQTT.

**Status: planning.** Most of the hardware is on hand, one part is still to be
ordered, and nothing has been connected to the bus yet.

## Why bother, when on/off control already exists

The EVU blocking contact is already wired and in use: 230 V switched by a Shelly
relay, exposed in Home Assistant as the switch "MLP EVU". That is SG Ready states
1 and 2 — one bit, and it can only ever take load *away*.

The target here is **heating curve control**. Raising the curve, or the room and
DHW setpoints, when there is solar surplus stores energy in the building mass and
the tank. That is a better instrument than SG Ready's "force on": it is
proportional, and it works *with* the heat pump's own logic instead of overriding
it.

| Instrument | Type | Use |
|---|---|---|
| EVU contact (Shelly) | one bit, hard | peak shaving, hard block on expensive hours |
| CAN parameter writes | continuous | curve and setpoint shifting, solar surplus |
| CAN reads | feedback | closes the loop on both of the above |

Writing is not blind reverse engineering: the FEK/FE7 room controller and the ISG
already write setpoints over this same bus, so mirroring what an existing
participant writes is a much smaller step than inventing traffic.

> Polarity of the existing Shelly is counter-intuitive — **relay ON = pump runs**.
> See [`../aidon/`](../aidon/) before writing automations against it.

## Architecture

```
Stiebel WPC 07
        │  CAN 2.0B, 20 kbps (expected, not yet measured)
        ▼
  MCP2515 + Adafruit CAN Pal (TJA1051T/3)
        │  SPI, all 3.3 V
        ▼
   ESP32 (or ESP8266)
        │  ESPHome native API
        ▼
 Home Assistant
```

## Hardware

**Available**

- ESP32, several boards (the measured one is ESP32-D0WD-V3 rev v3.1)
- ESP8266 Wemos D1 Mini — works equally well, fallback
- MCP2515 modules with TJA1050 transceiver (3 pcs — one is allowed to die)
- 120 Ω resistors — **not used**, this node taps an already-terminated bus

**Still needed**

- **Adafruit CAN Pal #5708** (TJA1051T/3 breakout) × 1
- PESD1CAN / NUP2105L TVS — only if the CAN Pal carries no bus protection
- LM2596 buck, if power is taken from the heat pump

Do **not** order until the bit rate is measured. The CAN Pal is useful either way;
nothing else is.

The ESP32 wins only on RAM headroom — Stiebel's element lists run to hundreds of
parameters, and 50–100 HA entities would get tight on an ESP8266. It does **not**
avoid the level-shifting work: it is a 3.3 V part too.

## The one modification that matters

The common MCP2515 + TJA1050 module is a 5 V design, because the TJA1050 needs
4.75–5.25 V. Wiring that straight to a 3.3 V MCU is wrong in both directions: the
module's outputs drive 0/5 V into a 3.6 V-max GPIO, and at VDD = 5 V the MCP2515's
input threshold is 3.5 V, above what the MCU can output.

**The solution: run the whole module at 3.3 V and bypass its transceiver with the
CAN Pal**, which generates its own 5 V on board. SPI is then entirely 3.3 V and no
level shifter is needed anywhere.

- Module VCC → 3.3 V (MCP2515 is in spec at 2.7–5.5 V)
- The on-board TJA1050 ends up under-volted and unused — its CANH/CANL terminals
  and its 120 Ω stay unconnected, so **neither needs removing**
- **Lift MCP2515 pin 2 (RXCAN)** and wire it to the CAN Pal's RX. This is the only
  mandatory rework — without it the TJA1050's RXD and the CAN Pal's RX fight over
  the same node
- MCP2515 pin 1 (TXCAN) → CAN Pal TX, tapped on the existing net

On the CAN Pal itself, **switch termination OFF**. Single most important setting
on the board: this node is a tap, not a bus end, and a third 120 Ω drops the bus
to roughly 60 Ω.

Full pin tables, the superseded two-rail plan and the grounding argument are in
[`CLAUDE.md`](CLAUDE.md).

## Three things that will bite you

1. **Check the crystal.** These modules ship with either an 8 MHz or a 16 MHz
   crystal. ESPHome defaults to 8 MHz, so a 16 MHz module with no `clock:` line
   gets the bit rate wrong by a factor of two and nothing works. Read the marking
   on the can.
2. **Listen-only is not optional.** A CAN node in normal mode acknowledges frames
   and emits error frames even if it never sends anything of its own — with the
   wrong bit rate it actively disturbs the heat pump's bus. If the installed
   ESPHome version does not expose listen-only on `mcp2515`, enforce it in
   hardware: lift the TJA1050's pin 1 (TXD) and tie it to VCC. The node then
   physically cannot drive the bus, and sweeping bit rates becomes risk-free.
3. **Grounding decides reliability.** If the Stiebel connector carries a supply
   voltage (the FE7/FEK bus normally does), take the ESP's power from there via
   the LM2596 — one ground reference, no loop. An ESP on laptop USB while
   connected to the heat pump bus is exactly the arrangement where loop currents
   run through the CAN conductors.

## Rejected: the ESP32's built-in CAN

`esp32_can` would have dropped the MCP2515, the SPI wiring and the level-shifting
problem in one go. ESPHome 2026.7.4 refuses the bit rate outright:

```
canbus.esp32_can: Bit rate 20KBPS is not supported on ESP32.
```

This is an **ESPHome limit, not a silicon limit** — the board on hand is a rev
v3.1 whose BRP divider reaches 20 kbps without trouble. The option reopens if
ESPHome ever exposes rates below 25 kbps. Cheap way to re-test after an upgrade,
no hardware needed:

```sh
podman exec esphome esphome config /config/cantest.yaml
```

## Remaining tasks

**Phase 1 — read**

- Locate CAN_H, CAN_L and GND on the WPC 07 (control board preferred, service
  RJ12 if the bus is exposed there)
- Verify the bit rate — stay listen-only until confirmed
- Capture frames, map frame IDs against the published element lists
- Create ESPHome sensors and expose them to Home Assistant

**Phase 2 — write**

- **Build a two-node bench bus first.** Two modified modules, 120 Ω at each end,
  nothing connected to the heat pump. Prove a frame goes out and arrives *before*
  joining a live system as an active participant. This is the only place those
  120 Ω resistors get used.
- Identify the writable elements: heating curve slope, room setpoint
  (comfort/ECO), DHW setpoint, operating mode
- Give the node a bus identity — address the WPM the way an FEK or ISG does
- **Rate-limit the writes.** If the WPM persists these parameters, writing every
  few seconds is an EEPROM wear problem. Write on change only, with a deadband and
  a minimum interval.
- **Make the offset self-clearing.** If HA dies while the curve is raised, the
  house overheats and the surplus optimisation turns into a cost. The write path
  needs the same watchdog thinking as the Shelly's Auto-ON timer: the baseline has
  to come back without HA being alive to restore it.

Full notes, wiring tables and reasoning: [`CLAUDE.md`](CLAUDE.md).

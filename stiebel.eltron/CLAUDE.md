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

# Prior art: this is the Elster protocol, and it is documented

The bus is not a Stiebel-specific unknown. It is the **Elster/Kromschröder CAN
protocol**, shared across Stiebel Eltron, Tecalor and related controllers, and it
has been reverse engineered thoroughly enough that phase 1 is a matching exercise
against a published table rather than blind decoding.

The canonical work is **Jürg Müller's `can_progs`** and its element list at
<http://juerg5524.ch/list_data.php> (HTTP only; mirror:
[andig/canprogs](https://github.com/andig/canprogs)). Everything below traces
back to it.

## What the sources confirm

- **20 kbps, 11-bit standard identifiers.** Two independent sources state it, so
  the "expected 20 kbps" in this file is a documented property of the protocol
  family, not a guess. It still gets confirmed by capture before this node
  transmits anything.
- **Device addresses are a fixed scheme**, which is what makes a capture
  readable:

  | CAN id | Device |
  |---|---|
  | 0x000 | direct |
  | 0x180 | boiler / heat pump |
  | 0x280 | ATEZ |
  | 0x300–0x303 | control modules (FEK / FE7 room control) |
  | 0x400 | room sensor |
  | 0x480 | manager (WPM) |
  | 0x500 | heating module |
  | 0x580 | bus coupler |
  | 0x600–0x603 | mixer modules |
  | 0x680 | PC / ComfortSoft |
  | 0x700 | external device |
  | 0x780 | DCF module |

- **The frame carries a command code** distinguishing write (0), read (1),
  response (2), acknowledge (3), write acknowledge (4), write response (5),
  system (6), system response (7), and large telegrams (0x20 / 0x21).
- **Community configurations address the pump as `3100` to read and `3000` to
  write** — the receiver 0x180 shifted right by three (0x30) with the command
  code in the low nibble. This is consistent with the scheme above, but the exact
  byte layout is **taken on trust until a capture confirms it**; do not encode it
  from this file alone.

## Implementations worth reading before writing any of our own

- [bullitt186/ha-stiebel-control](https://github.com/bullitt186/ha-stiebel-control)
  — ESPHome + Home Assistant, **3800+ Elster signals** in `ElsterTable.h`. The
  closest thing to a finished version of this project.
- [roberreiter/StiebelEltron-heatpump-over-esphome-can-bus](https://github.com/roberreiter/StiebelEltron-heatpump-over-esphome-can-bus)
  — ESPHome config that **reads and writes**, with the pump/FEK/own identifiers
  as variables.
- [andig/goelster](https://github.com/andig/goelster) — Go implementation of the
  protocol.
- [homeIoTDev/ElsterHeatingBridge](https://github.com/homeIoTDev/ElsterHeatingBridge)
  — .NET service, Tecalor/Stiebel, includes a bus scanner.
- [Home Assistant community thread](https://community.home-assistant.io/t/configured-my-esphome-with-mcp2515-can-bus-for-stiebel-eltron-heating-pump/366053)
  — long thread, MCP2515 specifics and the failure modes people actually hit.

Per repo convention none of this is copied here; it is linked at the source.

## What this changes for us

- **Phase 1 stops being decoding and becomes identification.** Capture, then
  match identifiers and element indices against the published table.
- **0x680 is not automatically free.** It is the PC/ComfortSoft address, and it
  is what the earlier draft config here used. Users in the community thread
  report it not working for them — an installed ISG or service tool may already
  occupy it, and two nodes sharing an identifier corrupts arbitration. The phase 1
  capture must therefore also answer *which addresses are already in use on this
  bus* before phase 2 picks one.
- **The ESP32's built-in TWAI does run this bus at 20 kbps** — bullitt186 uses
  exactly that. This supports the reading already recorded at the end of this
  file: the 25 kbps floor is ESPHome's `esp32_can` component, not the silicon.
  It does not change the MCU decision, because reaching it would mean adopting an
  external component instead of ESPHome's own.

---

# Existing Hardware

## Available

- **ESP8266 Wemos D1 Mini (NodeMCU)** — chosen MCU
- ESP32, several boards — reserve, see below. The one measured is ESP32-D0WD-V3 rev v3.1.
- MCP2515 CAN bus modules with TJA1050 transceiver (3 pcs)
- Dupont jumper wires
- Various resistors (including 120 Ω — not used, see Wiring)

## MCU choice

The D1 Mini. The ESP32 was in this plan for **its built-in CAN controller** — it
would have removed the MCP2515, the SPI wiring and the level-shifting rework in
one go. That route is rejected (see the end of this file: ESPHome will not do
20 kbps on `esp32_can`), and with it went the reason to prefer the ESP32.

The MCP2515 hangs off SPI identically on both, so what remains is **RAM
headroom**, and it is a phase 2 concern only. Stiebel's element lists run to
hundreds of parameters; if 50–100 of them end up as HA entities the ESP8266 gets
tight. Sniffing needs none of that, and a dozen entities the ESP8266 carries
without trouble.

**Switch only if the entity count actually forces it.** The move costs one board
and a pin change — `esp8266:` → `esp32:`, and the SPI pins to the VSPI defaults
(SCK 18, MISO 19, MOSI 23, CS 5). Nothing else in the configuration changes.

The board it would land on is the spare 30-pin DevKit (USB-C, CH340C, PCB
antenna) — see [`../pegasos.enervent/esp32-devkit.jpg`](../pegasos.enervent/esp32-devkit.jpg).
All four of those pins are brought out on it. The WROOM-32U on the shelf is not
available: it belongs to axioma.effection, and it is the wrong tool here anyway
since it needs an external antenna this project has no use for.

## Does the D1 Mini cope with phase 2 — writing?

Writing is not where the ESP8266 is weak. The MCP2515 does bit timing,
arbitration, acknowledgement and retransmission **in hardware**; the MCU only
moves frames across SPI. And the control loop is deliberately slow — write on
change, deadband, minimum interval — so nothing on the write path is
time-critical. A handful of writable parameters is a handful of `number:`
entities.

The pressure points are on the **read** side, in this order:

1. **RAM, if the read set balloons.** This is the one documented reason to move
   to the ESP32, and it is about how many sensors get created, not about writing.
2. **The MCP2515 has two RX buffers, and ESPHome polls them in `loop()`.** At
   20 kbps a full frame is roughly 6 ms on the wire, so a loop stall longer than
   about 12 ms — a WiFi reconnect, a long log burst — can drop frames. The
   component behaves the same on an ESP32; there is simply more slack. Keep the
   loop light: this is why the sniffer lambda uses a fixed buffer instead of
   building a `std::string` per frame, and why per-frame logging should go away
   once the identifiers are mapped.
3. **Do not become a device others depend on.** If the node only *requests* and
   reacts, a stalled loop costs a late read and nothing else. If it takes a bus
   identity that other participants poll and expect an answer from within a
   window, a stalled loop becomes visible on the heat pump's bus. That is a
   protocol-design decision in phase 2, and no MCU choice fixes it.

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

The **SN65HVD230** used to be listed here as surplus from the rejected
`esp32_can` route. That was a mistake — see below. It may remove the only
purchase this project has.

## The CAN Pal may not be needed at all

The CAN Pal was chosen for one headline reason: the TJA1051T/3 wants a 5 V
supply, and the board generates it from 3.3 V so that no second rail is needed.
That reasoning solves a problem **created by picking a 5 V transceiver in the
first place.**

The `SN65HVD230` already in the parts box is a **native 3.3 V CAN transceiver**.
It needs no 5 V, no rail generation and no level shifting; its logic side is
3.3 V by design. It was bought for the `esp32_can` route, but its function —
turn 3.3 V TX/RX into differential CAN — is exactly the function the CAN Pal was
going to buy.

Wiring is unchanged from the CAN Pal plan: lift MCP2515 pin 2 (RXCAN) to the
transceiver's RXD, MCP2515 pin 1 (TXCAN) to its TXD.

**It does not exist.** The SN65HVD230 was carried in this file as an already-owned
part from the first commit onward, but it is in no order history and it is not in
the parts box. The claim was wrong. **Phase 2 therefore needs a transceiver
bought.**

**If one is ever found, the question would be: breakout board or bare SO8 chip?**
A module (the common blue VP230 board with VCC / GND / CANH / CANL / RXD / TXD)
is a drop-in and the CAN Pal purchase disappears. A bare chip needs a carrier,
and then buying the CAN Pal is the lesser work. **Photograph it before ordering
anything.**

If it is a module, two details differ from the CAN Pal:

- **Termination.** VP230 boards usually carry 120 Ω, often soldered rather than
  on a jumper. It has to go — same reasoning as everywhere else in this file.
  The CAN Pal has a switch for it; this one may need desoldering.
- **The Rs pin (8).** Tie it to GND for high-speed mode, or to GND through
  10–100 kΩ for slope control. At 20 kbps slope limiting is a genuine benefit for
  EMC, and it is an option the CAN Pal does not offer.

Mixing a 3.3 V transceiver onto a bus whose other nodes are 5 V TJA1050s is
normal practice — CAN is differential and the levels interoperate.

**It does not have to be the Adafruit board.** Any 3.3 V CAN transceiver breakout
does the job: an SN65HVD230 / VP230 board, a TJA1051T/3 breakout, an MCP2562FD.
Two requirements only — the logic side must accept 3.3 V, and any on-board 120 Ω
must be removable or switchable. The CAN Pal is simply the one that was already
researched.

## An RS-485 module cannot stand in for the CAN transceiver

The JZK TTL↔RS-485 boards in stock look like an obvious substitute: differential
pair, same wiring, and the bus even runs at a serial-ish bit rate. **They will
not work, and the reason is not voltage but arbitration.**

- A CAN transceiver drives the dominant state actively and **releases the bus for
  the recessive state.** That is what lets several nodes talk at once and lets the
  loser back off. An RS-485 driver is push-pull: it drives both states, so two
  nodes disagreeing fight each other instead of arbitrating.
- CAN acknowledges every frame by having *other* nodes pull the bus dominant
  inside the ACK slot. A node that cannot receive and be overridden mid-frame
  cannot participate.
- These particular boards switch direction automatically from TX activity, which
  removes any possibility of holding the driver in the state CAN needs.

The differential pair is a coincidence of physical layer, not compatibility.

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

- Module VCC → 3.3 V. MCP2515 is in spec (2.7–5.5 V) and SPI is safe for the ESP.
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

## ESP ↔ MCP2515 module (single 3.3 V rail)

Drawn out in [`wiring-phase1.svg`](wiring-phase1.svg), with the signal-level
reasoning in [`schematic-phase1.svg`](schematic-phase1.svg).

The module's VCC pin feeds the whole board, MCP2515 and TJA1050 alike. On the
chosen solution that pin goes to **3.3 V and nothing else** — there is no second
rail to wire, in either phase. The difference between the phases is only which
transceiver sits on the bus side: the module's own TJA1050 while sniffing, the
CAN Pal once the RXCAN pin is lifted.

| MCP2515 module | Wemos D1 Mini | ESP32 (reserve) |
|----------------|---------------|-----------------|
| VCC | 3V3 | 3V3 |
| GND | G | GND |
| CS | D8 (GPIO15) | GPIO5 |
| SCK | D5 (GPIO14) | GPIO18 |
| SI (MOSI) | D7 (GPIO13) | GPIO23 |
| SO (MISO) | D6 (GPIO12) | GPIO19 |
| INT | — | — |

Both columns are the board's hardware SPI pins — nothing forces them, but
keeping them means no board-specific surprises.

**INT stays unconnected.** ESPHome's `mcp2515` component polls the controller in
its loop and takes no interrupt pin — wiring INT achieves nothing.

If the D1 Mini fails to boot, move CS off D8: GPIO15 must be low at boot, and a
CS line floating high before the MCU drives it holds it up. (On the ESP32, GPIO5
is a strapping pin too, but high is the level it wants, so CS is safe there.)

---

## MCP2515 ↔ Heat Pump

| MCP2515 module | Heat Pump |
|----------------|-----------|
| screw terminal H | CAN_H |
| screw terminal L | CAN_L |
| J4 GND | GND |

**The screw terminal has two poles only, H and L** — there is no ground pole on
it, so the bus ground reference joins at the J4 GND pin together with the ESP.
See [`mcp2515-module-prep.svg`](mcp2515-module-prep.svg).

**Disconnect the module's on-board 120 Ω terminator.** On this board it is a
jumper cap, so this needs no desoldering at all. The Stiebel bus is already
terminated at both ends; a third 120 Ω drops the impedance to roughly 60 Ω and
can break the heat pump's own traffic. The loose 120 Ω resistor in the parts box
stays in the box — this node is a tap, not a bus end.

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

- Bitrate: **20 kbps** — documented for the Elster protocol family (see Prior
  art), still to be confirmed on this unit before transmitting
- 11-bit standard identifiers
- Listen-only mode initially — see below
- 120 Ω termination only if located at the end of the CAN bus (this node is not)

## The crystal: 8 MHz, confirmed

These modules ship with either an 8 MHz or a 16 MHz crystal, and a 16 MHz module
configured as 8 MHz gets the bit rate wrong by a factor of two.

**The module in hand is marked `8.000` — 8 MHz.** That matches ESPHome's default
and the `can_clock: 8MHZ` substitution, so nothing needs changing. The board is
silkscreened V2139; see [`mcp2515-module.jpg`](mcp2515-module.jpg) for the board
itself and [`mcp2515-module-prep.svg`](mcp2515-module-prep.svg) for what to do to
it. Check the marking again if a different one of the three modules gets used.

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

1. **The 120 Ω is already out of circuit on this board — nothing to do.**
   Measured across the H and L screw posts: **49 kΩ**, three orders of magnitude
   away from a terminator. R2 is marked `121` = 120 Ω and it is on the board, but
   neither J1 nor J3 is shorted, so it never reaches the bus. The photograph
   looked like fitted jumper caps; it was wrong, and the meter settled it.

   Keep the reasoning below anyway, because it decides what to do with the *next*
   module — the other two are unmeasured. In this test the
   module's *own* transceiver and terminals are in use, so its terminator would
   sit across the live bus. Three terminators give ~40 Ω, below what the
   transceivers are specified to drive, and that can disturb the heat pump's own
   traffic. (In the final CAN Pal wiring the module's bus side is unused and the
   terminator is harmless.)

   **The decisive measurement is across the H and L screw posts, not across the
   jumpers.** Open or high → the terminator is not in circuit and there is
   nothing to do. Still ~120 Ω with both jumpers open → R2 is hard-wired and has
   to come off with an iron.

   **A worry that is now closed.** If one of those jumpers had been the link
   between the transceiver's CANH/CANL and the screw terminal, leaving it open
   would mean no bus connection at all — and the symptom would be zero frames,
   indistinguishable from a wrong bit rate. **Measured: TJA1050 pin 6 to the L
   post reads 0 Ω.** The terminal is wired straight to the transceiver, no jumper
   sits in that path, and a silent bus later will genuinely be about bit rate or
   wiring rather than a link that was never made.

2. **Enforce listen-only in hardware.** ESPHome's mcp2515 component may not expose
   listen-only mode. Rather than depend on it, **lift the TJA1050's pin 1 (TXD) and
   tie it to the module's VCC** (TXD high = recessive).

   **Pin 1 is the top pin of U1's left-hand row** — the side away from the screw
   terminal, identified on the board and ringed in
   [`mcp2515-module-prep.svg`](mcp2515-module-prep.svg). That is consistent with
   the rest of the package: with pin 1 there, the terminal side carries 8, 7, 6, 5
   downwards, putting CANH (7) at the H post and CANL (6) at L.

   **Confirmed on the board, from three directions:** pin 6 reads 0 Ω to the L
   post, pin 2 to the module's GND and pin 3 to VCC. The orientation is measured,
   not inferred, so pin 1 can be lifted without further checking.

   The procedure, for the next module. Board unpowered,
   continuity mode. Pin 7 beeps to the H post and pin 6 to the L post — copper
   traces, so under an ohm and unchanged when the probes are swapped, which is
   what separates them from the junction paths that make everything else read
   finite. Pin 8 is then the neighbour of pin 7 at the corner, and pin 1 sits
   directly across the package from pin 8. Confirm before touching it: pin 2 must
   beep to the module's GND pin and pin 3 to VCC. Three independent checks, and
   the cost of getting it wrong is a destroyed transceiver. The node then physically
   cannot drive the bus: no ACK, no error frames, whatever bit rate is configured.

   Dedicate one of the three modules as the permanent sniffer this way. The MCP2515
   will go error-passive because its transmissions are never acknowledged — that is
   internal to the chip and never reaches the bus.

With TXD lifted, sweeping bit rates is risk-free. Try 20 → 25 → 50 kbps until
frames appear.

---

# ESPHome Configuration

The phase 1 sniffer is [`stiebel.eltron.yaml`](stiebel.eltron.yaml). It reads
and logs; it writes nothing, and it is not the phase 2 configuration.

`board: d1_mini` assumes 4 MB of flash, and `esptool flash_id` confirms it:
**Detected flash size: 4MB**, chip ESP8266EX. The listing said "4MBit", which
would have been 512 kB and too small for OTA — a wording error, now settled by
reading the chip rather than trusting either the listing or the board profile.

The USB bridge on the board that was flashed is an **FT232R, not the CH340G the
listing described**, so `ftdi_sio` covers it and no CH34x driver is needed. Its
DTR/RTS are wired: `esptool` resets the board into the bootloader on its own, and
no manual GPIO0 handling is needed.

**The two unknowns are `substitutions:` at the top of the file** — crystal and
bit rate. Both are one-line edits followed by a re-flash, because ESPHome fixes
the bit rate at compile time; there is no way to sweep it at runtime.

**`mode: LISTENONLY`** is what makes the sweep safe on a live bus. **It compiles
on ESPHome 2026.8.2** — the version matters, because this whole question was
about whether the installed one exposes the option. It does, so listen-only is
enforced in software and **the TXD lift is no longer needed.**
Phase 1 requires no soldering at all: the termination was already out of circuit
and the only remaining modification has just become optional.

Keep it in mind anyway as the hardware belt to the software braces. The two
protect against different mistakes, and if a future ESPHome upgrade ever drops
the option, the lift is what makes a bit-rate sweep safe again.

The build lands at **flash 45.2 %, RAM 40.0 %** on a D1 mini — comparable to
aidon's 46.8 % / 53.3 %, so there is room for the sensor set that phase 1 will
grow.

**`can_id: 0x000`** is the transmit identifier. It is never used, because
nothing is transmitted, but the schema requires the key. It is not a bus
identity; that decision belongs to phase 2 and to the FEK/ISG behaviour it has
to mirror.

**Two `on_frame:` triggers, both with `can_id_mask: 0x000`.** A zero mask
matches every identifier — this is a sniffer, so filtering is the opposite of
what is wanted. The protocol is documented as 11-bit standard identifiers, so
the extended trigger exists only to prove that on the first capture; delete it
once it has stayed silent.

**The `CAN frames` counter** answers "is the bit rate right?" without reading
the log at all: it stays at zero on a wrong rate and climbs steadily on a
correct one. That is worth an entity of its own during a sweep that may take
several re-flashes.

## The two failure signatures, and why they must not be confused

With the module unwired the boot log says:

```
[C][canbus:020]: config standard id=0x000
[E][component:143]: canbus is marked FAILED: unspecified
```

That is the **SPI** signature: the MCP2515 does not answer, so the component
never starts. It appears whether the module is absent, miswired or unpowered.

A wired and working module removes that line entirely. What can still happen
after that is `CAN frames` sitting at zero — the **bus** signature: the
controller is alive and configured, but nothing decodes, which points at the bit
rate or at CANH/CANL.

Confirm the FAILED line is gone **before** going anywhere near the heat pump.
Tested together at the pump the two produce the same visible symptom — nothing
happens — and the sweep would be chasing the wrong variable.

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
- Map identifiers and element indices against Jürg Müller's element list (see
  Prior art).
- Record which addresses are already occupied on this bus — phase 2 needs one
  that is free, and 0x680 may not be.
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
  ISG does — **using an identifier the phase 1 capture showed to be free.**
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

Nothing for phase 1. For phase 2, one transceiver.

- **A 3.3 V CAN transceiver breakout** × 1 — Adafruit CAN Pal #5708, or an
  SN65HVD230 / VP230 board, or any equivalent. The SN65HVD230 this file used to
  claim was in stock does not exist, so this is a real purchase. Order it when
  phase 1 has confirmed the bit rate, not before.
- PESD1CAN or NUP2105L (SOT-23) — only if the chosen transceiver board carries no
  bus protection
- LM2596 or similar buck, if power is taken from the heat pump. Note that
  hirvirata also wants one; the stock count is not recorded anywhere.

Nothing is needed for phase 1 at all. Do **not** order until the bit rate is
measured and the SN65HVD230 has been looked at.

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

Consequence: the SMD rework on the MCP2515 module is unavoidable. But **the
SN65HVD230 does not become surplus** — see "The CAN Pal may not be needed at
all". It was bought for this route, and it is still a 3.3 V CAN transceiver on
the shelf.

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

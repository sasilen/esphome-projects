# Stiebel Eltron WPC 07 → Home Assistant (CAN bus)

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

Read the heat pump's operating data over its CAN bus and — in phase 2 — write the
parameters the WPM exposes, straight from Home Assistant via ESPHome. No MQTT.

**Status: phase 1 works, phase 2 waits for one part.** The sniffer
[`stiebel.eltron.yaml`](stiebel.eltron.yaml) is flashed and sitting on the bus
at X27. The bit rate is confirmed at 20 kbps, frames are captured and decoded in
the log, and the addresses in use are known. What is left in phase 1 is naming
the elements against the published table and turning them into Home Assistant
sensors. Writing needs a transceiver that is chosen but not yet in hand.

**Phase 1 needs no transmitter after all.** The bus polls itself at 91 frames a
minute with no gap longer than five seconds, so a listen-only node sees every
temperature the controller reads. That was the open question, and it is closed.

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

Writing is not blind reverse engineering. **The capture caught the machine
writing to itself** — the manager writes four elements to another node on a
fixed cycle and reads each value back to confirm it. Those frames are recorded
byte for byte, so phase 2 imitates traffic that already exists rather than
inventing any.

And it has been done before. This is the **Elster/Kromschröder CAN protocol**,
reverse engineered years ago and published as an element list of thousands of
signals, with working ESPHome configurations that both read and write. What is
left of phase 1 is matching a capture against that table, not decoding from
scratch.

> Polarity of the existing Shelly is counter-intuitive — **relay ON = pump runs**.
> See [`../aidon/`](../aidon/) before writing automations against it.

## Architecture

```
Stiebel WPC 07
        │  Elster protocol, 20 kbps, 11-bit ids — measured, not assumed
        ▼
  MCP2515 + TJA1050        phase 1, listening: the module as it ships
        │                  phase 2, writing: swap the bus side for an
        │                  SN65HVD230 and lift one MCP2515 pin
        │  SPI, all 3.3 V
        ▼
  ESP8266 (Wemos D1 mini)
        │  ESPHome native API
        ▼
 Home Assistant
```

## Hardware

**Available**

- ESP8266 Wemos D1 Mini — the chosen board
- ESP32, several boards — reserve for phase 2 (the measured one is
  ESP32-D0WD-V3 rev v3.1)
- MCP2515 modules with TJA1050 transceiver (3 pcs — one in use, two spare against
  a botched pin lift in phase 2)
- 120 Ω resistors — not used at first. The bus measured 150 Ω de-energised, so it
  carries **no terminator**; start without one and reconsider only if traffic is
  unreliable

**Still needed — nothing for phase 1**

- **An SN65HVD230 (VP230) breakout** for phase 2, €2–4, chosen and not yet in
  hand. Not the Adafruit CAN Pal at €20: its 5 V generator solves a problem a
  native 3.3 V transceiver does not have, and its switchable termination stopped
  mattering once the bus measured unterminated. See [`CLAUDE.md`](CLAUDE.md).
- PESD1CAN / NUP2105L TVS — only if the transceiver board carries no protection
- LM2596 buck, if power is taken from the heat pump — five are in stock

The RS-485 modules in stock are **not** a substitute; see [`CLAUDE.md`](CLAUDE.md)
for why.

The ESP32 was here for its built-in CAN controller, and that route is rejected
(see below). What is left is RAM headroom — Stiebel's element lists run to
hundreds of parameters, and 50–100 HA entities would get tight on an ESP8266.
That is a phase 2 question. The ESP32 does **not** avoid the level-shifting
work: it is a 3.3 V part too.

## What the MCP2515 module actually provides

Two chips on one board, and they play different roles:

- **MCP2515 — the CAN controller.** Bit timing, arbitration, acknowledgement,
  error handling, filters, buffers. It talks SPI to the ESP. This is the part
  that makes the project possible at all: neither ESP has a usable CAN controller
  here, since ESPHome refuses 20 kbps on the ESP32's built-in one. **Nothing
  replaces it, and it is not the problem.**
- **TJA1050 — the transceiver.** Turns the controller's logic-level TX/RX into
  the differential bus. It works, but it wants 4.75–5.25 V.

So the module is not short of a transceiver. The mismatch is that the two chips
want different supply voltages once a 3.3 V MCU is involved, and only the
transceiver half is affected:

| Phase | What is needed | Cost |
|---|---|---|
| 1, listen only | The module alone, whole board at 3.3 V. The under-volted TJA1050 still receives, and nothing is ever transmitted | nothing |
| 2, transmit | A transceiver that drives the bus from 3.3 V. The MCP2515 stays; only its bus side moves to the new part | one small board |

Phase 1 confirmed the first row in practice: the under-volted TJA1050 receives a
live bus for hours on end. The stalls that did occur are the MCP2515 driver's
doing, not the transceiver's — see [`CLAUDE.md`](CLAUDE.md).

Three modules therefore cover three controllers. The phase 2 purchase replaces a
job the on-board TJA1050 cannot do at 3.3 V, not the module.

## The one modification that matters

The common MCP2515 + TJA1050 module is a 5 V design, because the TJA1050 needs
4.75–5.25 V. Wiring that straight to a 3.3 V MCU is wrong in both directions: the
module's outputs drive 0/5 V into a 3.6 V-max GPIO, and at VDD = 5 V the MCP2515's
input threshold is 3.5 V, above what the MCU can output.

**The solution: run the whole module at 3.3 V and bypass its transceiver with a
native 3.3 V one.** SPI is then entirely 3.3 V, and so is the bus side, so no
level shifter and no second rail is needed anywhere.

For phase 1 this costs nothing at all — the under-volted TJA1050 receives
perfectly well, and a listening node never has to drive a dominant bit. The
rework below belongs to phase 2, when the SN65HVD230 arrives:

- Module VCC → 3.3 V (MCP2515 is in spec at 2.7–5.5 V)
- The on-board TJA1050 ends up under-volted and unused — its CANH/CANL terminals
  and its 120 Ω stay unconnected, so **neither needs removing**
- **Lift MCP2515 pin 2 (RXCAN)** and wire it to the new transceiver's RXD. This
  is the only mandatory rework — behind pin 2 is an output, and without the lift
  the TJA1050's RXD and the SN65HVD230's fight over the same node
- MCP2515 pin 1 (TXCAN) → the new transceiver's TXD, tapped on the existing net.
  Behind pin 1 is an input, so tapping is enough

Drawn out in [`phase2-transceiver.svg`](phase2-transceiver.svg). Note that the
new board's own 120 Ω is soldered rather than switchable, and on this
unterminated bus that is probably wanted rather than a nuisance — the opposite
of the advice that applied while the pump was assumed to terminate the bus.

Full pin tables, the superseded two-rail plan and the grounding argument are in
[`CLAUDE.md`](CLAUDE.md).

## Four things that will bite you

1. **Check the crystal.** These modules ship with either an 8 MHz or a 16 MHz
   crystal, and a 16 MHz board configured as 8 MHz gets the bit rate wrong by a
   factor of two. The module photographed for
   [`mcp2515-module-prep.svg`](mcp2515-module-prep.svg) reads `8.000`, so this
   one is settled — but read the can on whichever board you actually use.
2. **Listen-only is not optional.** A CAN node in normal mode acknowledges frames
   and emits error frames even if it never sends anything of its own — with the
   wrong bit rate it actively disturbs the heat pump's bus. If the installed
   ESPHome version does not expose listen-only on `mcp2515`, enforce it in
   hardware: lift the TJA1050's pin 1 (TXD) and tie it to VCC. The node then
   physically cannot drive the bus, and sweeping bit rates becomes risk-free.
3. **Grounding is less of a trap than it looks, but check before you assume it.**
   X27 pin 4 does carry a supply — 17.4 V, not the 12 V the legend promises — and
   pin 3 has no continuity to the chassis, so the rail is floating SELV. That
   means an ordinary Class II charger is as isolated as taking power from the
   pump through an LM2596, and the real risk is narrower: **plugging USB into the
   ESP while it sits on the bus**, from a mains-earthed laptop. Debug over WiFi
   and the question does not arise. See [`CLAUDE.md`](CLAUDE.md).
4. **The receiver stops silently.** The MCP2515 latches an overflow flag that the
   driver never clears, and reception then ends for good with the node still
   online and the log still clean. It happened twice in a two-hour capture. A
   watchdog in the configuration restarts the node after two minutes without a
   frame; do not remove it without checking the warning count first.

## First run — the sniffer

This is what was done, and what to repeat if the node is ever rebuilt. Phase 1
runs on one plain module, unmodified, and that module becomes the permanent
sniffer.

Three drawings cover this, and they answer different questions:
[`mcp2515-module-prep.svg`](mcp2515-module-prep.svg) — what to change on the
board; [`schematic-phase1.svg`](schematic-phase1.svg) — why the circuit is what
it is; [`wiring-phase1.svg`](wiring-phase1.svg) — which pin goes where, and the
order to check things in. The board itself is in
[`mcp2515-module.jpg`](mcp2515-module.jpg).

1. **Prepare the module — there is nothing to do.** Termination is already out of
   circuit on the module measured for these drawings: across the H and L screw
   posts it reads 49 kΩ, three orders of magnitude away from a terminator. And
   `mode: LISTENONLY` compiles on the installed ESPHome, so listen-only is
   enforced in software and the TJA1050 pin 1 lift is unnecessary. **Phase 1
   needs no soldering.** Repeat the 49 kΩ measurement if you use one of the other
   two modules — a reading near 120 Ω means R2 is hard-wired and has to come off.
2. **The crystal is already known: 8 MHz**, so the `substitutions:` block in
   [`stiebel.eltron.yaml`](stiebel.eltron.yaml) needs no edit. Check the marking
   anyway if you grab a different module from the box.
3. **Wire it at 3.3 V** — the whole module, single rail. Pin table in
   [`CLAUDE.md`](CLAUDE.md).
4. **Flash and check it boots** before going anywhere near the heat pump.

ESPHome runs in its own container on the Home Assistant host, and the board is
plugged into a different machine. That splits the first flash in two, exactly as
it did for [`../aidon/`](../aidon/BUILDLOG.md) — compile there, write here. The
work happens in the **ESPHome dashboard**, not on a command line:

1. **New Device** → name it `wpc-can`. Choose the **empty configuration** if the
   dialog offers one; otherwise run the wizard, pick ESP8266, and **Skip** the
   install offer. *Import from file* is cleaner still, but only works when the
   YAML is already in the host's `/config`. The board does not need to be
   connected, and it does not need to be on this machine.
2. **Edit** the device and replace the wizard's file with this project's YAML.
   The wizard writes a literal `api:` key; move it to secrets as
   `api_encryption_key` so the file matches what is in the repo. The dashboard
   has a secrets editor in its menu.
3. **Validate.** If the device menu offers *Validate*, use it. Otherwise
   **Install → Manual download** — configuration errors appear before compilation
   starts, so a rejected `mode:` shows up immediately either way.
4. The same **Manual download** produces the binary once compilation succeeds.

Note that the dashboard names the file after the device, so on the host it will
be `wpc-can.yaml` while the repo keeps `stiebel.eltron.yaml` to match its
directory. Same content, two naming conventions.

**Try `Install → Plug into this computer` first.** It compiles on the server and
then flashes over serial from the machine running the *browser*, which is exactly
this situation and needs no file handling at all. The catch is that the browser's
WebSerial requires a secure context: it works when the dashboard is reached over
HTTPS or localhost, and is blocked on a plain `http://` LAN address. That is
probably why the aidon build went the manual route.

If that option is missing or fails, take the **Manual download** binary to the
machine holding the board and write it over USB, either from `web.esphome.io` in
a Chromium-based browser — that site is HTTPS, so WebSerial works — or with
esptool:

```sh
sudo esptool --port /dev/ttyUSB0 --baud 115200 write_flash 0x0 firmware.bin
```

Use the plain or `factory` binary, not `-ota.bin`. Drop to `--baud 57600` if the
connection breaks. `Hash of data verified` means it took.

**Only the first flash needs USB.** After that the board is on WiFi and
`Install → Wirelessly` reaches it — which is how every change since has gone on,
and why no isolated transceiver is needed: the node is never tethered to a
laptop while it sits on the bus.

One thing differs from the aidon build: there is no wizard to generate the API
key, so make one yourself with `openssl rand -base64 32` and put it in
`secrets.yaml`. **No CH34x driver was needed** — the listing claimed a CH340G,
but the board that was flashed carries an FT232R, which `ftdi_sio` already
covers and which resets into the bootloader on its own.

5. **Connect CANH, CANL and GND** to the bus and watch the `CAN frames` counter.
   Zero means the bit rate is wrong: edit `can_bit_rate`, re-flash, try again.
   The rate is compile-time, so each step is a re-flash.

No sweep was needed in the end — 20 kbps was right at the first attempt and
frames appeared as soon as the bus was connected. A zero counter here means the
bit rate or the wiring and nothing else: the bus is never quiet for more than
five seconds.

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

**Phase 1 — read.** Connected at X27 on board A2, bit rate confirmed, protocol
decoded, addresses censused, elements matched against the published list. Left
to do:

- **Name what the list does not cover.** Everything the panel asks for is named
  — tank setpoint and actual, return temperature, flow setpoint, operating mode,
  the clock. The manager's own range above 0xFE07 is missing from the list
  entirely, and three names it does carry are wrong for this machine. That part
  has to be named from behaviour; see [`CLAUDE.md`](CLAUDE.md)
- **Check the outdoor sensor.** `AUSSENTEMP` did not move by a tenth of a degree
  in two hours, and heating curve control depends on it being live
- Work out what **0x100** is — it is one of the busiest nodes on this bus and it
  is not in the published address table
- **Validate and flash the sensors.** Nine entities are written — three
  temperatures, two setpoints, the operating mode, the pump's own clock, the
  compressor and one unidentified signal — and checked against the capture, but
  not yet against ESPHome or the node itself
- **Identify 0xFE07.** It runs whenever 0xFE1B is off, in states where nothing
  is being heated, so it is not the compressor. That anti-correlation is the
  thread to pull
- Re-capture now that the watchdog window is two minutes rather than thirty

**Phase 2 — write**

- **Build a two-node bench bus first.** Two modified modules, 120 Ω at each end,
  nothing connected to the heat pump. Prove a frame goes out and arrives *before*
  joining a live system as an active participant. This is the only place those
  120 Ω resistors get used.
- Identify the writable elements: heating curve slope, room setpoint
  (comfort/ECO), DHW setpoint, operating mode
- **Take 0x680 as the node's bus identity.** It is the only address in the
  published table that never appeared in two hours of capture. 0x301 is *not*
  free — a mixer module writes to it
- **Copy the machine's own write-then-verify pattern.** The manager writes four
  elements to 0x700 on a fixed cycle and reads each value back; those frames are
  on record in [`CLAUDE.md`](CLAUDE.md), so phase 2 imitates rather than invents
- **Rate-limit the writes.** If the WPM persists these parameters, writing every
  few seconds is an EEPROM wear problem. Write on change only, with a deadband and
  a minimum interval.
- **Make the offset self-clearing.** If HA dies while the curve is raised, the
  house overheats and the surplus optimisation turns into a cost. The write path
  needs the same watchdog thinking as the Shelly's Auto-ON timer: the baseline has
  to come back without HA being alive to restore it.

Full notes, wiring tables and reasoning: [`CLAUDE.md`](CLAUDE.md).

# Stiebel Eltron WPC 07 → Home Assistant (CAN bus)

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

Read the heat pump's operating data over its CAN bus and — in phase 2 — write the
parameters the WPM exposes, straight from Home Assistant via ESPHome. No MQTT.

**Status: planning.** Most of the hardware is on hand, one part is still to be
ordered, and nothing has been connected to the bus yet. The phase 1 sniffer
configuration [`stiebel.eltron.yaml`](stiebel.eltron.yaml) is written but has
not been flashed or validated against a real ESPHome install.

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

And it has been done before. This is the **Elster/Kromschröder CAN protocol**,
reverse engineered years ago and published as an element list of thousands of
signals, with working ESPHome configurations that both read and write. Read
[`CLAUDE.md`](CLAUDE.md) before capturing anything — phase 1 is matching a
capture against a known table, not decoding from scratch.

> Polarity of the existing Shelly is counter-intuitive — **relay ON = pump runs**.
> See [`../aidon/`](../aidon/) before writing automations against it.

## Architecture

```
Stiebel WPC 07
        │  Elster protocol, 20 kbps, 11-bit ids (documented, not yet measured)
        ▼
  MCP2515 + Adafruit CAN Pal (TJA1051T/3)
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
- 120 Ω resistors — **not used**, this node taps an already-terminated bus

**Still needed — nothing for phase 1**

- **A 3.3 V CAN transceiver breakout** for phase 2: Adafruit CAN Pal #5708, an
  SN65HVD230 / VP230 board, or equivalent. The requirements are only that the
  logic side takes 3.3 V and that any on-board 120 Ω can be removed.
- PESD1CAN / NUP2105L TVS — only if the transceiver board carries no protection
- LM2596 buck, if power is taken from the heat pump — five are in stock

The RS-485 modules in stock are **not** a substitute; see [`CLAUDE.md`](CLAUDE.md)
for why. Do **not** order until the bit rate is measured.

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

Three modules therefore cover three controllers. The phase 2 purchase replaces a
job the on-board TJA1050 cannot do at 3.3 V, not the module.

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
3. **Grounding decides reliability.** If the Stiebel connector carries a supply
   voltage (the FE7/FEK bus normally does), take the ESP's power from there via
   the LM2596 — one ground reference, no loop. An ESP on laptop USB while
   connected to the heat pump bus is exactly the arrangement where loop currents
   run through the CAN conductors.

## First run — the sniffer

The CAN Pal is not needed yet. Phase 1 runs on one plain module, and that module
becomes the permanent sniffer:

Three drawings cover this, and they answer different questions:
[`mcp2515-module-prep.svg`](mcp2515-module-prep.svg) — what to change on the
board; [`schematic-phase1.svg`](schematic-phase1.svg) — why the circuit is what
it is; [`wiring-phase1.svg`](wiring-phase1.svg) — which pin goes where, and the
order to check things in. The board itself is in
[`mcp2515-module.jpg`](mcp2515-module.jpg).

1. **Prepare the module — there is nothing to do.** Termination is already out of
   circuit on the module measured for these drawings: H to L reads 49 kΩ. And
   `mode: LISTENONLY` compiles on the installed ESPHome, so listen-only is
   enforced in software and the TJA1050 pin 1 lift is optional. **Phase 1 needs
   no soldering.** Repeat the 49 kΩ measurement if you use one of the other two
   modules.
   Pull the termination jumper cap; measuring across the H and L screw posts tells
   you when it is out (~120 Ω → open). Then lift the TJA1050's pin 1 (TXD) and tie
   it to VCC. That pin lift is the only soldering here, and it is optional if you
   trust `mode: LISTENONLY` on its own.
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
`Install → Wirelessly` reaches it, which matters here because bit-rate sweeping
means several re-flashes.

Two things differ from the aidon build: there is no wizard to generate the API
key, so make one yourself with `openssl rand -base64 32` and put it in
`secrets.yaml`; and the machine doing the USB write needs the **CH34x driver**,
since these D1 minis carry a CH340G over USB-C.

5. **Connect CANH, CANL and GND** to the bus and watch the `CAN frames` counter.
   Zero means the bit rate is wrong: edit `can_bit_rate`, re-flash, try again.
   20 → 25 → 50 kbps. The rate is compile-time, so each step is a re-flash.

Once frames appear, capture a long log and start mapping identifiers against the
element lists.

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

- Connect at **X27 on board A2** — 1 = H, 2 = L, 3 = ground, 4 = +12 V. Verify
  with the meter first; see [`bus-connection.svg`](bus-connection.svg)
- Verify the bit rate — stay listen-only until confirmed
- Capture frames, map identifiers and element indices against the published
  element list
- **Note which addresses are already in use** — 0x680 is the PC address and may
  be taken. Phase 2 needs a free one
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

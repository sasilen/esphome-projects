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
- **The byte layout is confirmed by capture.** It was taken on trust from
  community configurations until 2026-09-05; a live capture then matched it
  exactly:

  ```
  0x480 → E1 00 FA FE 4C 00 00      read request
  0x700 → 92 00 FA FE 4C 00 12      response, value 0x0012
  ```

  `0xE1` is `0xE0 | 1`: the high nibbles are the receiver shifted right by three
  (`0xE0 << 3` = 0x700) and the low nibble is the command, 1 = read. `0x92` is
  `0x90 | 2` — receiver 0x480, command 2 = response. `FA` marks an extended
  element index in the next two bytes, and the last two carry the value. So the
  WPM at 0x480 polls device 0x700 for element 0xFE4C and is answered 18.

- **Both index forms occur, and the capture shows when each is used.** Elements
  below 0x100 go straight into byte 2 with the value in bytes 3–4; larger ones
  use the `FA` marker and shift everything along:

  ```
  0x100 → 31 00 0C 00 00 00 00      short form, read element 0x0C
  0x180 → 22 00 0C 00 93 00 00      response, value 0x0093
  0x480 → E1 00 FA FE 4C 00 00      extended form, read element 0xFE4C
  0x700 → 92 00 FA FE 4C 00 12      response, value 0x0012
  ```

- **A write was caught live**, which is the operation phase 2 has to imitate:

  ```
  0x480 → E0 00 FA FE 1B 00 64      command 0 = write, element 0xFE1B := 100
  0x700 → 92 00 FA FE 1B 00 64      response echoes the value
  ```

  `0xE0` is the same receiver 0x700 with command nibble 0. So writing is not
  something this project has to invent — the WPM does it on this bus already, and
  the frame to copy is on record.

- **Six addresses are occupied: 0x100, 0x180, 0x301, 0x480, 0x601, 0x700.**
  Matching the scheme, that is a comfort panel polling the boiler, the manager
  talking to an external device, and a mixer module talking to a control
  module. **0x680 is the only listed address that never appears** in two hours
  of capture, so it is the candidate for this node's own identity in phase 2.
  See "What a two-hour capture contains" for how each was seen.

- **A seventh address in the log is a corrupted identifier, not a discovery.**
  An overnight capture produced one frame from id 0x078 and one from 0x784.
  Neither can be a node: the scheme puts the address in the high nibble and 0–3
  in the low bits, so every real identifier is a multiple of 0x080 plus 0–3.
  0x078 is the one that decodes — its seven bytes were `92 00 FA FE 1C 00 00`,
  a byte-perfect response to 0x480 for element 0xFE1C, which only 0x700 sends,
  and 0 is one of the two values 0x700 ever reports for that element. The
  payload survived and the identifier did not.

  **That does not make the frames themselves fictional**, and 0x784 is the
  counterexample: its payload repeats an earlier capture's byte for byte, so
  something real is sending it under an identifier that cannot be read reliably.
  See "The overnight run happened" for what each of the two settles and what it
  leaves open. The rule here is narrower than either: **an identifier outside
  the scheme is not to be printed as a node**, which is why the YAML's shape
  check rejects one and logs the frame raw. Two such frames and 315
  same-millisecond duplicates in 95 000 is the normal cost of monitoring
  silently, not a wiring fault.

- Values look like tenths: element 0x0E answers 0x01F2 = 498, element 0x16
  answers 0x0112 = 274, element 0x0C answers 0x0093 = 147. As °C those are 49.8,
  27.4 and 14.7 — plausible flow, return and source temperatures, and the scaling
  to check first against the element list.

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
- **0x680 was not automatically free, and the capture is what settled it.** It
  is the PC/ComfortSoft address, and users in the community thread report it not
  working for them — an installed ISG or service tool may already occupy it, and
  two nodes sharing an identifier corrupts arbitration. On this machine it never
  appeared in two hours, so it is free here. That is a property of this
  installation, not of the protocol.
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
transceiver's RXD, MCP2515 pin 1 (TXCAN) to its TXD. Drawn out in
[`phase2-transceiver.svg`](phase2-transceiver.svg), together with the
configuration changes that go with it.

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

**Buy the SN65HVD230, not the CAN Pal.** The Adafruit board costs around €20; the
blue VP230 module does the same job for €2–4, often in packs of three. Both of the
CAN Pal's selling points have lost their value here:

- Its **on-board 5 V generator** solves a problem that only exists with a 5 V
  transceiver. The SN65HVD230 is a native 3.3 V part and needs no 5 V at all.
- Its **switchable termination** mattered while the bus was assumed to be
  terminated already. It is not — so a soldered 120 Ω on the cheaper board is no
  longer a drawback, and might even be wanted as the bus's only terminator.

Two things to check on a VP230 when it arrives: the **Rs pin (8)** wants a
connection to ground, directly or through 10–100 kΩ for slope limiting, which at
20 kbps is a free EMC improvement; and the **120 Ω** is usually soldered rather
than switchable, so decide before installing rather than after.

### The board chosen

The bare six-pad breakout — `3V3, GND, CTX, CRX, CANH, CANL` in one row, headers
supplied loose, two resistors marked **R1** and **R2**. Three of them cost what a
single Waveshare-branded board does, and the Waveshare turned out to be the same
design with a screw terminal added and its 120 Ω soldered just the same.

**No screw terminal, and that is fine.** Solder the bus wires straight into the
CANH and CANL holes; 0.75 mm² solid is about the diameter a 2.54 mm hole takes,
and a soldered joint outlasts a screw clamp in a permanent install anyway. Fit
the supplied header on the logic side only, so the SPI-side jumpers stay
serviceable while the bus side stays fixed.

On arrival, read the two resistors. **R2 sits between CANH and CANL** and should
be marked `121` — that is the 120 Ω terminator, and on this unterminated bus
leaving it in place is probably right. **R1** is the Rs slope-control resistor;
its value decides whether the transceiver runs in high-speed or slope-limited
mode.

Three boards also means the phase 2 pin lift on the MCP2515 stops being the
nervous operation it would be with one.

**Isolation was considered and is not needed here.** The argument for an
ISO1050-class board was the ground loop created by plugging USB into the ESP
while it sits on the bus. Two findings remove it: the bus reference is a floating
SELV rail, so a Class II supply creates no loop by itself, and this node is
debugged entirely over WiFi — ESPHome serves logs through the API and updates
over OTA, with safe mode as the recovery path. The one situation that would need
serial access is a board that will not boot, and that means carrying it to the
bench, off the bus.

What remains is transient coupling from a cabinet that switches compressor
contactors, and a **TVS diode covers that at a fraction of the cost**. Buy the
plain transceiver and the TVS.

## Would a single all-in-one board have been the better buy?

Boards exist that carry an ESP32 and a CAN transceiver together — Waveshare
ESP32-S3-RS485-CAN, LilyGO T-CAN485 and similar. No SPI wiring, no level
shifting, no crystal to read, no termination jumper to hunt. As hardware they are
plainly tidier than an MCP2515 module and a D1 mini.

**They would not have solved this project's actual blocker.** All of them use the
ESP32's built-in TWAI controller, and ESPHome's `esp32_can` refuses bit rates
below 25 kbps. Stiebel runs at 20. The nicer board would have hit exactly the
wall already documented at the end of this file, and the way out would have been
an external component instead of ESPHome's own.

That is the shape of the trade: **the MCP2515 looks more primitive, but ESPHome
supports it at 20 kbps natively.** The simpler hardware would have moved the
complexity into software, where it is harder to see and harder to hand over.

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

### The tap point: X27 on board A2

Drawn out in [`bus-connection.svg`](bus-connection.svg). The source is the wiring
diagram in Stiebel's own **WPC 04–13 cool Operation and Installation** manual,
which is not kept in this repo — manufacturer documentation is linked at source,
not copied, and `.gitignore` keeps stray PDFs out. Fetch it from the Stiebel
[document portal](https://www.stiebel-eltron.com/) or ManualsLib and keep the
working copy outside the repo.

The diagram carries an explicit pin legend next to the connector:

| X27 pin | Legend | Use |
|---|---|---|
| 1 | `1 = H` | CAN high |
| 2 | `2 = L` | CAN low |
| 3 | `3 =` (symbol, not text) | reference / ground **by elimination** |
| 4 | `4 = +12V` | bus supply — **measures 17.4 V**, see below |

The same three-signal group appears elsewhere in the diagram as `H`, `L`, `“+”`,
which is how Stiebel labels this bus throughout. It is the FE7/FEK room-control
bus: four wires, of which two are the CAN pair.

**Two things follow.**

**The bus carries a supply, and that settles the power question.** A permanent
install can take the ESP's supply from pin 4 through the LM2596, giving one
common ground reference and no loop — which is exactly what the grounding
section below asks for. It also means pin 4 must never reach the transceiver.

**Measured, not 12 V: pin 4 sits at 17.4 V.** The legend says `+12V`; the rail is
evidently unregulated and rises above nominal at light load. Consequences: the
LM2596 handles it comfortably (its input range starts at 3.2 V and runs to 46 V),
but its output must be set to 5.0 V *before* anything is connected, because a
mis-set trimmer now delivers 17.4 V into the ESP rather than 12. And the figure
to design against is the measured one, not the printed one.

**Pins 1 and 2 measure a steady 2.5 V** to the reference, which is the CAN
recessive level and confirms the pair independently of the legend.

**And it says the bus was idle at that moment.** A meter averages: under traffic
CAN_H reads a little above 2.5 V and CAN_L a little below. Exactly 2.5 V on both
means nothing was moving.

That sets a trap for the next step, because **a quiet bus and a wrong bit rate
produce the same reading — a frame counter at zero.** Sweeping 20 → 25 → 50 kbps
against a silent bus proves nothing and can discard the correct rate.

**Provoke traffic instead of waiting for it.** Work the heat pump's own control
panel: navigating menus makes the display talk to the controller over this same
bus.

**That reasoning was sound and its conclusion was wrong.** No FEK or FE7 room
control is installed, so this file concluded that nothing polls the bus on a
schedule and that traffic always has to be provoked. The capture says otherwise:
the bus carries **over 200 frames a minute, continuously**, and the longest gap
between two frames in two hours is 4.7 seconds. The manager polls the machine
every five seconds whether anyone is looking or not.

So the flat 2.5 V reading meant something narrower than it seemed. A meter
averaging a differential pair that is recessive most of the time reads 2.5 V on
both lines regardless — at 20 kbps a seven-byte frame occupies a few
milliseconds, and the duty cycle simply does not move a multimeter. The
measurement never was evidence about traffic.

**Two conclusions that rested on it are withdrawn.** Provoking traffic from the
panel is unnecessary; a zero frame counter means a wrong bit rate or bad wiring
and nothing else. And **address 0x301 is not free** — 0x601 writes to it and it
answers 0x100, so a control module of some kind is installed even if it is not
an FEK. Phase 2 takes 0x680.

### The connector takes pushed-in wire, not screws

X27 is a spring terminal. It accepts **solid conductor**, stripped 8–10 mm and
inserted bare, or stranded wire with a bootlace ferrule crimped on.

**Never tin the end.** Solder cold-flows under the constant pressure of a clamp:
the contact force bleeds away over months, resistance climbs, and the result is
an intermittent joint that is nearly impossible to find later. This holds for
screw terminals equally. Tinning also solves a problem solid wire does not have —
it exists to keep strands together, and a solid conductor is already one piece of
copper.

A length of Cat5e is the convenient source: **installation cable** has solid
conductors and the pairs are already twisted — take one pair for H and L, and a
third conductor for ground. Check which kind is at hand, because Cat5e comes
both ways: the stiff in-wall cable is solid and goes in bare, while a flexible
patch cord is stranded and needs a ferrule. If a single conductor feels too thin
for the clamp, fold the stripped end double into a hairpin rather than reaching
for solder.

**If the wire will not push in, use the release slot.** These terminals have a
second opening beside the conductor hole: press a small flat screwdriver into it
and the spring opens, letting the wire enter without having to force the clamp
apart by itself. Only stiff solid conductor can be pushed in directly — anything
softer needs the slot, and that is what it is there for.

Tug each wire gently after inserting. A spring terminal either holds or it does
not, and it tells you immediately.

**Pin 3 is confirmed as the reference — but not by continuity to earth.** Its
label is a symbol the text extraction could not recover, so it was inferred at
first. What confirms it is that every other reading makes sense against it: pins
1 and 2 sit at 2.5 V to pin 3, and pin 4 at 17.4 V to pin 3.

**It has no continuity to the chassis, and that is normal.** The bus supply is a
floating SELV rail, deliberately not bonded to protective earth. An earlier
version of this file suggested checking pin 3 against the frame and expecting
0 Ω — that test is wrong for an isolated supply, and following it would have led
to rejecting the correct pin.

**There is no terminator on this bus.** Measured de-energised, H to L reads
**150 Ω**. A 120 Ω terminator anywhere in parallel would make that impossible,
since a parallel combination never exceeds its smallest member. The community
claim that the heat pump terminates the bus itself does **not** hold for this
machine. Worth reversing the probes to check: if the reading changes with
polarity it is a semiconductor path inside the transceiver rather than a resistor.

That does not block anything — 20 kbps over a short stub tolerates an
unterminated bus. And if traffic turns out to be unreliable, the fix costs
nothing: the module's own 120 Ω (R2) is present on the board and merely
disconnected, so it is a jumper away rather than a soldering job.

Note that an earlier search result claiming `X72` is the CAN connector on WPC
models is **wrong for this machine** — in this diagram X72 sits on board A5 among
the relays K5–K7. Checking it against the actual document is what caught that.

- **A worked example from a different family**, for comparison only:
  [bullitt186](https://github.com/bullitt186/ha-stiebel-control) documents the
  WPL 13 E service connector as pin 3 = CAN-H, pin 5 = CAN-L, pin 7 = GND — and
  warns in the same breath that other models use a completely different connector
  and pinout. **WPC is a different series. Do not transfer these numbers.**
- The same source states the bus runs at **20 kbps** and that the heat pump
  terminates it itself. The bit rate still stands as the expectation; **the
  termination claim does not survive measurement on this machine** — see above,
  H to L reads 150 Ω de-energised.

### Identifying the pair with a meter, before trusting any pinout

This works on an unknown connector and does not depend on the manual:

1. **Power the heat pump down.** Between CAN_H and CAN_L you should read roughly
   **60 Ω** — two 120 Ω terminators in parallel. No other pair on the connector
   reads that. This alone identifies the pair.
2. **Power it back up and measure to GND.** Idle, both lines sit near **2.5 V**.
   Under traffic CAN_H rises and CAN_L falls symmetrically around that point.
3. **A supply pin shows a steady DC voltage** to GND, typically well above 5 V.
   Find it and stay away from it — it must never reach the transceiver.

Only after 1 and 2 agree with each other is the pair identified. Then connect.

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
- **Switchable termination** — 60 Ω + 60 Ω split, 120 Ω across the bus. Start
  with it **OFF**, but the reason has changed: this bus turned out to carry no
  terminator at all, so the question is open rather than settled. If traffic
  proves unreliable, switching it on is the first thing to try — a single 120 Ω
  is a lighter load than the 60 Ω transceivers are designed to drive.
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
air. Having three modules still helps — but note what the spares are actually
for. No module is consumed: phase 1 uses one unmodified, and phase 2 lifts a
single pin on that same board, which is a modification rather than damage. The
two spares are insurance against tearing a pad or cooking the chip during that
one operation, not a planned casualty.

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

This section was written expecting the bus reference to be tied to earth, which
would have made taking power from the bus the only clean option. **Measurement
changed the picture:** X27 pin 3 has no continuity to the chassis, so the supply
is a floating SELV rail.

That has a pleasant consequence. **A Class II supply — an ordinary phone charger
— is electrically just as isolated as the LM2596 route**, because neither end is
referenced to earth and there is no second path for a loop. The remaining risk is
not the power supply at all: it is **plugging a USB cable into the ESP while it
is on the bus**, which is what happens whenever the node is debugged from a
mains-earthed laptop. That is an argument for an isolated transceiver, not for
where the 5 V comes from.

So the LM2596 route is now optional rather than required, and it carries two
costs of its own:

- **It loads the pump's own supply.** That rail feeds the FE7/FEK and is sized
  for it. An ESP8266 averages ~80 mA and peaks far higher on WiFi transmit; check
  the rail holds up before trusting it.
- **A fault in our node reaches the heat pump.** If bus power is used, put a small
  inline fuse or polyfuse in the +17.4 V feed so that a short in the buck or the
  ESP cannot disturb the pump's electronics.

Either way: measure the connector voltages before connecting anything, and never
feed bus supply voltage into the transceiver.

---

# CAN Bus Settings

Confirmed on this WPC 07 by capture, 2026-09-05:

- Bitrate: **20 kbps**. No sweep was needed — the first configured value was
  right, and frames appeared as soon as the bus was connected.
- **11-bit standard identifiers**, as documented. The extended-id trigger stayed
  silent through the capture and has been removed from the configuration.
- Addresses occupied: **0x100, 0x180, 0x301, 0x480, 0x601, 0x700**. Only
  **0x680** is free, and that is what phase 2 takes.
- Bus load: **220-240 frames a minute**, sustained, with no gap longer than
  4.7 s.
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

   Dedicating one module as a permanently crippled sniffer was the plan while this
   modification looked mandatory. **It is not needed.** `mode: LISTENONLY` compiles,
   so no module gets cut, and the same board carries straight through to phase 2 —
   where the rework is on the *controller* side anyway: lift MCP2515 pin 2 (RXCAN)
   to the new transceiver, tap pin 1 (TXCAN) to its TX, and leave the on-board
   TJA1050 unused. The MCP2515 is never replaced; only the bus-facing half is.

   If the lift is done anyway as a belt-and-braces measure, expect the MCP2515 to go
   error-passive: its transmissions are never acknowledged. That is internal to the
   chip and never reaches the bus.

Sweeping bit rates is risk-free in listen-only mode. Try 20 → 25 → 50 kbps until
frames appear.

---

# What a two-hour capture contains

Captured 2026-09-05, 16:02–17:56, 10 380 frames. The log itself is not in the
repo — `.gitignore` keeps `*.log` out, and the findings below are the part worth
keeping.

## The bus polls itself, and that decides the architecture

**Over 200 frames a minute, sustained, with no gap longer than 4.7 seconds.**
Two independent polling loops run without anyone touching the machine: 0x480
asks 0x700 every five seconds, and 0x100 asks 0x180 every ten.

**An earlier figure of 91 a minute in this file was wrong**, and the mistake is
worth keeping because it is easy to repeat: 10 380 frames over a 113-minute span
is 92 a minute, but 69 of those minutes were a stalled receiver. Dividing by the
live 44 minutes gives 236, and a later clean run measured 222 over its first two
and a half minutes. **A rate averaged across an outage is not a rate.**

The correction matters beyond arithmetic: the load on the ESP8266's loop and the
risk of filling the MCP2515's two receive buffers both scale with the real
figure, not the diluted one.

**So phase 1 needs no transmitter.** A passive node sees flow temperature,
return temperature and compressor state at the rate the manager itself reads
them, which is far faster than any sensible Home Assistant update interval.
Writing stays a phase 2 problem, and it stays a problem about *control*, not
about reading.

## The address census

Counted as sender, over 10 380 frames:

| Address | Frames | Role in the scheme | What it does here |
|---|---|---|---|
| 0x480 | 4562 | manager (WPM) | polls 0x700, serves the clock to 0x100 |
| 0x700 | 4149 | external device | answers the manager's five-second poll |
| 0x100 | 868 | **not in the table** | polls 0x180, asks 0x480 for the time |
| 0x180 | 792 | boiler / heat pump | answers 0x100 |
| 0x601 | 8 | mixer module | writes to 0x301 every seven minutes |
| 0x301 | 1 | **heating circuit 1** | answered 0x100 once |

**0x680 never appears**, so the PC/ComfortSoft address is free on this machine
and phase 2 takes it. **0x301 is occupied** — the earlier guess that it was free
because no FEK is installed was wrong, and 0x601 writing to it is the proof.

**A list from a WPF 10 — same protocol family, different model — names four of
these six:**

| | WPF 10 says | Seen here |
|---|---|---|
| 0x180 | Kessel | ✓ answers the panel's temperature polls |
| 0x301 | **Heizkreis 1** | ✓ answered a `VORLAUFSOLLTEMP` of 25.0 |
| 0x302 | Heizkreis 2 | not present |
| 0x480 | Manager | ✓ polls 0x700, serves the clock |
| 0x601 | **Mischermodul** | ✓ **holds the heating curve** |

**0x601 being the mixer module is the row that matters**, because 0x010E
`HEIZKURVE` lives there and that is what phase 2 exists to write. A curve
belonging to a mixer module is the natural arrangement — the module is what
mixes to a flow temperature, so the curve deciding that temperature is its
parameter. This file had inferred "mixer" from the 0x600–0x603 block in Jürg
Müller's scheme; a real machine's own list now says it outright.

`Heizkreis 1` at 0x301 lands the same way: the one thing that address ever
answered was a heating circuit's flow setpoint.

The same source lists 0x401–0x404 as sensors in the display and 0x69E–0x6A2 as
displays, neither of which appears here.

**The two it does not name are the two busiest on this bus.** Neither 0x100 nor
0x700 is on the WPF 10, and between them they carry most of the traffic.

0x700's role is legible from behaviour even so. The manager polls it every five
seconds for flow and return temperatures and writes it four commanded outputs
including the compressor — **which is exactly what bullitt186's `HEIZMODUL` does
at 0x500 on a different machine.** So 0x700 is very likely this model's heat
pump module, at an address the family does not standardise. That also explains
the element list's blind spot: the 0xFDxx and 0xFExx signals belong to a
compressor module, and the published table is oriented to `KESSEL` and
`MANAGER`.

0x100 behaves like a display — polling the boiler for temperatures, asking the
manager for the date and time — but matches no display address in any list to
hand.

### There are no separate boxes: this is one cabinet talking to itself

**This installation has no room controllers of any kind.** The only things
attached are an outdoor sensor and the heat pump's own panel. So none of these
addresses is a device on a wire — they are **functions inside the WPC's own
controller, each given a bus identity.**

That resolves what looked like a contradiction all evening. This file recorded
that no FEK or FE7 room control is installed, and then found 0x601 holding
`RAUMSOLLTEMP_TAG`, `RAUMSOLLTEMP_NACHT` and the heating curve — parameters a
room control unit would own. Both are true: the *parameters* exist because a
heating circuit needs them, and the machine serves them from a logical endpoint
whether or not any physical controller is present to display them.

It also explains why the addresses here match no other machine's list. A WPC 07
is a compact unit, and what other installations spread across separate modules
this one implements internally: manager at 0x480, heat pump module at 0x700,
panel at 0x100, tank at 0x180, heating circuit at 0x301, circuit parameters at
0x601. The bus is an internal backplane, not a field bus.

**Two consequences worth carrying into phase 2.**

Writing the curve to 0x601 is not addressing a separate box — it is addressing
the machine's own controller through the identity it answers on. The captured
frame works regardless, which is the point of having captured it rather than
reasoned about it.

And with no room sensor anywhere, `RAUMSOLLTEMP_TAG` at 26.0 is not a
temperature anyone is trying to reach. It is the curve's parallel shift, which
is precisely the lever the solar-surplus idea wants — and it is safe to move in
a way a real room target would not be.

It does carry one caution for phase 2. Displays living at 0x69E–0x6A2 sit close
to the 0x680 this node intends to take. 0x680 stayed silent through every
capture on this machine, so the choice stands — but the address scheme is
evidently not universal, and that is worth knowing before trusting it elsewhere.

### bullitt186's implementation confirms three things independently

[ha-stiebel-control](https://github.com/bullitt186/ha-stiebel-control) is a
working node on this same protocol, and reading its `docs/ARCHITECTURE.md` and
`archive/README.md` settles questions this file had answered only from capture:

- **Its ESP32 transmits as `PC`, CAN id 0x680** — the same address phase 2
  intends to take, arrived at independently. A choice made here by elimination
  turns out to be the convention.
- **The byte-0 encoding is confirmed by working code.** Its `CanMember` table
  gives read and write id pairs of `{0x31, 0x00}` and `{0x30, 0x00}` for
  `KESSEL` at 0x180, `{0x91, 0x00}` / `{0x90, 0x00}` for `MANAGER` at 0x480, and
  `{0xA1, 0x00}` / `{0xA0, 0x00}` for `HEIZMODUL` at 0x500. Every one is the
  receiver shifted right by three with the command in the low nibble, which is
  exactly what this file derived from the capture. **The decode was right, and
  now it is right for a reason other than our own arithmetic.**
- **Its list of universal signals matches what the menu walk found**: date and
  time, EVU lock, operating mode, energy counters. Those are the elements every
  Elster machine carries, which is why they were the ones the element list named
  cleanly and the 0xFDxx range was not.

**And one thing not to copy from it.** Its archived version used **0x700** as
the ESP client's own address. On this bus 0x700 is a busy participant answering
the manager every five seconds, so taking it here would collide head-on. The
current version's 0x680 is the one to follow.

A detail that follows for phase 2: with this node at 0x680, **responses
addressed to it will carry `0xD2` in byte 0** — 0x680 shifted right by three is
0xD0, plus command 2. That is the pattern to filter on once the node starts
asking questions of its own.

### The addressing rule, confirmed five times over

[valexi7's fork](https://github.com/valexi7/ha-stiebel-control) carries a
`CanMembers` table that includes sub-addressed members, which is the case this
project actually needs:

| Member | Address | Read id |
|---|---|---|
| `PUMP` | 0x180 | `{0x31, 0x00}` |
| `FE7X` | 0x301 | `{0x61, 0x01}` |
| `FEK` | 0x302 | `{0x61, 0x02}` |
| `MANAGER` | 0x480 | `{0x91, 0x00}` |
| `FE7` | 0x602 | `{0xC1, 0x02}` |

Every one is the receiver shifted right by three in byte 0 with the command in
the low nibble, and **the low bits of the address in byte 1** — 0x301 and 0x302
share `0x61` and differ only in byte 1, exactly as 0x601 and 0x600 would.

**That validates the captured write byte for byte.** Writing 0x010E to 0x601
means `{0xC0, 0x01}`, which is precisely what the panel sent and what this file
recorded as `C0 01 FA 01 0E 00 18`. The phase 2 frame is now confirmed against
both a live capture and a working implementation.

**One field in that table is stale — do not copy it.** `ESPCLIENT` sits at 0x680
but its `ConfirmationID` is `{0xE2, 0x00}`, and 0xE0 shifted left by three is
**0x700**, not 0x680. It is the value from bullitt186's archived version, where
the client really was at 0x700, left behind when the address changed. For a
client at 0x680 the confirmation byte is `0xD2`.

**And the 0x600 block has two different names in two sources.** The WPF 10 list
calls 0x601 `Mischermodul`; this table calls 0x602 `FE7`, a room control unit.
Both fit what 0x601 does here — it holds the circuit's slope and room setpoints,
which is a job either device performs. The name does not change the address or
the element, so phase 2 is unaffected.

**0x100 is the open question.** It is not in the published address table, yet it
is the third busiest node here. Its behaviour — polling the boiler for
temperatures and asking the manager for the date and time — is exactly what a
display would do.

## The clock group, decoded end to end

Six elements the manager serves to 0x100 identify themselves without any element
list at all, because their values can be checked against a calendar:

| Element | Value | Reading |
|---|---|---|
| 0x0122 | 5 | day |
| 0x0123 | 9 | month |
| 0x0124 | 26 | year |
| 0x0125 | 18 | hour |
| 0x0126 | 0–59 | **minute** |
| 0x0112 | 2 | `PROGRAMMSCHALTER`, the operating mode |

The minute is not inferred: 0x0126 rises by exactly one every sixty seconds
across the whole capture and rolls 59 → 0, with the hour written in the same
breath. That is a clock, and it confirms the byte layout, the command nibble and
the element indexing all at once against something already known.

**Two things fall out of it.**

**The heat pump's clock is eleven minutes fast.** It rolled to 18:00 while the
capture clock read 17:49:05, and the offset is the same at every sample. Worth
correcting on the panel — it shifts every time-of-day function in the machine,
including any tariff window.

**Some elements are byte-swapped.** Every value in this group is a multiple of
256: the number sits in byte 5 and byte 6 is padding. Read as a 16-bit word the
hour reads 4608 rather than 18. The decoder cannot tell from a single frame, so
it prints the raw hex alongside — but when mapping, **a value that is always a
multiple of 256 is byte-swapped, not a scaled integer.**

The element list has a name for exactly this: all six carry type
`et_little_endian`. The observation and the table were arrived at
independently and agree, which is the strongest evidence in this file that the
decode is right end to end.

## The room thermostats cap the curve, and that weakens the plan

**The floor loops have their own room sensors, and they act alone.** They
throttle flow to hold setpoints nobody else knows — not the heat pump, not the
bus, not Home Assistant. The machine runs open loop: curve plus outdoor
temperature gives a flow temperature, and the rooms help themselves to as much
of it as their valves allow.

That undercuts the reasoning this project was started on. The README argues that
raising the curve on solar surplus **stores energy in the building mass**,
proportionally, and that this beats SG Ready's blunt "force on". The mechanism
does not survive contact with thermostatic valves:

- raise the curve → flow temperature rises
- rooms approach their own setpoints → valves throttle
- **heat into the building is limited by the valves, not by the curve**

The storable surplus is bounded by whatever slack the thermostats happen to
allow — the gap between where each room sits and where its own dial is set — and
**nothing on the CAN bus can widen that gap.** Turning the curve up further does
not help once the valves have closed.

**The DHW tank has no such limiter, and that changes which lever to build
first.** `EINSTELL_SPEICHERSOLLTEMP` at 0x180 raises a setpoint with real
storage behind it and nothing throttling in between: a tank taken from 50 °C to
55 °C absorbs surplus and gives it back as hot water that would otherwise have
been made later at a worse time. That is the clean, effective sink, and it was
the secondary target in the original plan rather than the primary one.

**So phase 2's ranking should invert.** DHW setpoint first, because it works.
Curve second, because it is capped by hardware this project does not control
and cannot see.

### The electric element is a third lever, and it is about speed, not efficiency

**This file briefly claimed the electric element had delivered twelve megawatt
hours. It had not, and conservation of energy is what caught it.**

The 2WE counters read `WAERMEERTRAG_2WE_WW_SUM_MWH = 9` and
`..._HEIZ_SUM_MWH = 3`, which looked like a heavily used immersion heater. Set
that against the rest of the same menu walk:

| | |
|---|---|
| Electricity in, hot water | 522 kWh + 7 MWh = **7.52 MWh** |
| Heat out, hot water | 961 kWh + 18 MWh = **18.96 MWh** |
| Implied COP | 2.5, entirely plausible |

**An electric element is COP 1.** Delivering 9 MWh of heat would take 9 MWh of
electricity — more than the machine drew for hot water in total, heat pump
included. The claim is arithmetically impossible, and
`WAERMEERTRAG_2WE_WW_TAG_KWH = 893` — 893 kWh in a single day — is absurd on its
own terms.

So **those indices do not mean what the table says on this machine**, and the
element is off, exactly as the installation's owner said. Jürg Müller's list
warns in its own header that not every index is correct; this is what that looks
like from the inside.

**The habit worth keeping from this: check a table's claim against a
conservation law before believing it.** The element list has been right about
temperatures all evening, which made it easy to trust here — but a temperature
has nothing to contradict, while an energy has a budget it must fit inside.

`NHZ_ANZAHL_STUFEN` at 0x05A0 answering with the 0x8000 sentinel now reads as
corroboration rather than a puzzle: no stages configured, because there is
nothing configured to run.

**Which changes the answer to "can the boost be forced?"** If the element is
disabled in configuration, a bus write would first have to re-enable it — a
different and larger decision than triggering a boost, and one somebody made
deliberately. If it is off at the breaker, no write will do anything at all.
**Establish which before spending any effort on the elements below.**

### The panel overturns all of that: the element has run, and it ran last night

The reasoning above is left standing because the method in it is sound and the
conclusion is wrong, which is worth being able to see at once. **The premise
that failed is the meaning of one abbreviation.**

The second page of LÄMPÖMÄÄRÄ — never opened until the second walk — reads:

```
NHZ LV SUMMA        9.896 MWh
```

Elements `0x0925` = 9 and `0x0923` = 896. With `NHZ LÄMM SUMMA` = 3.311 MWh from
the first page that is **13.2 MWh delivered by the electric element**, and the
twelve-megawatt-hour claim this file called impossible is understated rather
than absurd.

**The impossibility argument rested on treating 7.52 MWh as the machine's total
hot water electricity. It is not.** Every row on the TEHONKULUTUS screen begins
`VD` — *Verdichter*, the compressor — and there is no NHZ row on it at all. The
reheat's electricity is not counted there. Read correctly the numbers are
consistent and unremarkable:

| | |
|---|---|
| Compressor electricity, hot water | 7.526 MWh |
| Compressor heat, hot water | 18.972 MWh → COP 2.52 |
| Element heat, hot water | 9.896 MWh, at COP 1 |
| Element heat, heating | 3.311 MWh |

**And the element is not off.** `0x0923` read **893 at 19:41 on 5 September** and
**896 at 07:34 the next morning** — three kilowatt-hours of hot water delivered
electrically overnight, during the same capture that recorded the tank reaching
55.5 °C. The running hours agree: 134 h on stage 1, 132 h on stage 2, 5922 h on
both.

So `KÄYTTÖRAJA HZG` and `KÄYTTÖRAJA WW` reading `POIS` means **no operating
limit is set**, not that the function is disabled — the reheat is permitted at
any outdoor temperature. The 0x8000 on `NHZ_ANZAHL_STUFEN` stays unexplained,
but it is no longer corroboration of anything.

**The lesson survives its own counterexample, with a correction.** Checking a
table against a conservation law was the right instinct and it did catch a real
inconsistency — but the budget it was checked against was the wrong budget.
Before declaring something impossible, confirm what the denominator actually
measures. A counter labelled for one component is not the machine's total, and
on this panel the three letters that say so are easy to read past.

**Candidates for forcing it, none confirmed on this machine:**

| Element | Name | Effect |
|---|---|---|
| 0x05AB | `MANUELL_NHZ_STUFE` | direct manual stage override |
| 0x0589 | `NHZ_VERZOEGERUNG_WW` | delay before the element engages for DHW |
| 0x058A | `NHZ_AUSSENTEMP_SOFORT_WW` | outdoor temperature below which it engages at once |
| 0xFDAB | `ZWEITER_WE_STATUS` | **feedback** — whether it is actually running |

None appeared in the menu walk, which proves nothing: these are service-level
parameters a display has no reason to show. **They are settled by reading them,
and reading is transmitting**, so this is phase 2 work.

**The economics have to be stated, because they are not obvious.** The element
is COP 1 and the heat pump is perhaps COP 3, so pushing surplus into the tank
electrically costs roughly three times the electricity per stored kilowatt hour.
That only pays when the price ratio beats 3:1, or when the surplus is
genuinely worthless otherwise.

**Speed is the real argument for it.** If the cheap window is an hour or two,
the heat pump cannot move enough energy in time and the element can. The choice
is then not about efficiency at all but about whether the charge fits the
window:

| Window | Lever |
|---|---|
| long and cheap | raise the DHW setpoint, let the heat pump work |
| short and very cheap | the element, accepting COP 1 |

`ZWEITER_WE_STATUS` matters more than the forcing elements, whichever is used:
without it there is no way to tell whether a write did anything, and a control
loop that cannot observe its own actuator is not a control loop.

### And the counters found tonight can settle it

This does not have to stay an argument. `WAERMEERTRAG_*` and
`EL_AUFNAHMELEISTUNG_*`, split by heating and hot water, came out of the menu
walk. **Raise the curve by a step on a mild day and watch whether heating energy
delivered actually rises**, and by how much against the electricity taken. If it
barely moves, the valves are absorbing the change and the argument above is
right. If it rises cleanly, the thermostats have more slack than expected and
the original plan stands.

That is a day's measurement with entities that already exist, and it should be
run before any control logic is written against the curve.

## Walking the panel menus is the single most productive thing to do

Six minutes of browsing every menu on the heat pump's own display produced **82
distinct (sender, element) pairs, 75 of them named by the element list.** Two
hours of passive listening produced about twenty.

The reason is structural. The panel polls a handful of elements continuously and
reads the rest **only when a human is looking at them**, so a menu walk turns a
passive sniffer into a survey of everything the machine is willing to talk
about. It costs nothing, needs no code, and is repeatable whenever the map has a
hole in it.

### It found what phase 2 exists to write

| Device | Element | Name | Type | Value |
|---|---|---|---|---|
| **0x601** | **0x010E** | **`HEIZKURVE`** | cent | **0.23** |
| 0x601 | 0x0005 | `RAUMSOLLTEMP_I` | dec | 26.0 |
| 0x601 | 0x0008 | `RAUMSOLLTEMP_NACHT` | dec | 23.0 |
| 0x180 | 0x0013 | `EINSTELL_SPEICHERSOLLTEMP` | dec | 55.0 |
| 0x180 | 0x0A06 | `EINSTELL_SPEICHERSOLLTEMP2` | dec | 50.0 |
| 0x180 | 0xFDB4 | `SOMMERBETRIEB` | little_bool | off |

**The heating curve is the whole point of this project**, and it now has an
address, an index, a type and a current value. It lives on 0x601 — the mixer
module — not on the manager, which is not where this file would have guessed.

`RAUMSOLLTEMP_I` at 26.0 is not a room temperature anyone is targeting: with no
room sensor installed these act as the curve's parallel shift, which is exactly
the lever the solar-surplus idea wants.

### And it found the feedback side

- **0x480 / 0x0074 `EVU_SPERRE_AKTIV`, and its polarity is settled.** Two
  readings against a known Shelly state did it:

  ```
  19:41:27   480>100 resp  e=0074 = 1      Shelly permitting
  19:53:18   480>100 wr    e=0074 = 0      Shelly off, i.e. blocking
  ```

  **1 means permitted and 0 means blocked**, so the element tracks the contact,
  not the block — despite a name that reads the other way round. That is the
  same inversion the Shelly itself has, which this repo already warns about, and
  it would have been an easy way to build an automation that does exactly the
  opposite of what it says.

  **The manager writes this rather than waiting to be asked.** The change
  arrived as a command 0 to the panel seconds after the relay moved, so EVU
  state is observable passively and needs no polling — which matters, because
  polling means transmitting and phase 1 does not.

  One loose thread: that write carried `+0001` in the short form's spare bytes,
  where the value itself was 0 and the previous value had been 1. Tempting to
  read as "what it changed from", but the same spare bytes on 0x000E carry
  numbers no previous reading explains, so it stays unexplained.

  0x1388 jumped from 0 to 8246 (0x2036) four seconds later, having been 0 in
  every earlier sample. Coincident with the block, and worth watching.
- **Energy counters, daily and cumulative, split by heating and hot water**:
  `WAERMEERTRAG_*` for heat delivered and `EL_AUFNAHMELEISTUNG_*` for electricity
  taken. Those two together are a measured COP, which is a better argument for
  or against any control strategy than anything this file currently reasons
  from.
- `LZ_VERD_1_*` compressor run hours, `MASCHINENDRUCK`, `QUELLE_IST` at 4.2.

### 0x8000, 0x9000 and 0x8080 are "not present", not values

They turn up 26 times across the survey and they decode as absurdities —
`BIVALENZALTERNATIVTEMPERATUR` at −2867.2 °C, `VERFLUESSIGER_TEMP` at −3276.8.
**They are sentinels for an unconfigured or absent parameter**, and any sensor
built on an element that can return them needs to drop them rather than publish
them. 0x8080 is the same thing for `et_time_domain`, where the list's own code
already tests for it.

**The panel says what 0x9000 means, and it is narrower than "absent".** On all
three screens where a sentinel-answering element is displayed the machine
prints `POIS` — the function is switched off. See "The panel walk" below; the
guard is the same either way, but a sentinel in the log is not a fault report.

### The write, captured

Nudging the curve one step on the panel produced it:

```
19:48:13.818   100>601 wr   ex=010E = 24 (0x0018)      the panel writes 0.24
19:48:19.921   601>100 resp ex=010E = 24 (0x0018)      confirmed on the next poll
```

**This is the frame phase 2 has to send**, for the parameter phase 2 exists to
control, and nothing about it has to be generalised from anything else:

| | |
|---|---|
| CAN identifier | the sender's own — **0x680** for this node |
| byte 0 | `0xC0` — receiver 0x601 shifted right by three, command 0 = write |
| byte 1 | `0x01` — the receiver's low bits, which is what makes it 0x601 and not 0x600 |
| bytes 2–4 | `FA 01 0E` — extended index marker, then element 0x010E |
| bytes 5–6 | `00 18` — 24, and `et_cent_val` makes that 0.24 |

So the complete payload is `C0 01 FA 01 0E 00 18`, and only the value bytes
change.

**The write is not acknowledged, and that is the surprise.** Nothing answered it
at all. The confirmation at 19:48:19 is 0x601 answering a *poll* six seconds
later, on the panel's normal cycle — not an acknowledgement of the write.

That is a different contract from the one this file recorded earlier. Writes
from 0x480 to 0x700 are answered in the same millisecond, which is where the
"write-then-verify is the machine's own pattern" note came from. **It is the
machine's pattern with that module, not with this one.** For 0x601 the pattern
is write, then read back on your own schedule and check.

A second write settled it beyond doubt. Restoring the curve to 0.23 was
confirmed **1.46 s** later, against 6.1 s the first time — and the confirmation
arrived in a batch with 0x0008 and 0x4EA7, which is the panel's routine sweep of
the whole 0x601 group:

```
19:56:09.092   100>601 wr   ex=010E = 23
19:56:10.258   601>100 resp  e=0008 = 230       the panel's poll group,
19:56:10.553   601>100 resp ex=4EA7 = -28672    not an answer to anything
19:56:10.553   601>100 resp ex=010E = 23
```

**The varying delay is the proof.** An acknowledgement has a fixed latency; a
poll that happens to come round does not. Where in the cycle the write lands is
all that differs.

Phase 2 therefore cannot treat silence as failure. A curve write that produces
no response is normal; the only way to know it took is to ask.

### The clock is no longer eleven minutes fast

`Heat pump clock` read `2026-09-05 19:48` at a wall-clock 19:48:20 during the
same session — in step, where it had been eleven minutes ahead. The drift is
historical, and the entity is what will show it if it returns.

## Naming the elements: the table covers half this bus

Matched against Jürg Müller's element list. `juerg5524.ch` did not answer over
either HTTP or HTTPS, so the work was done against the
[andig/canprogs](https://github.com/andig/canprogs) mirror of `ElsterTable.inc`
and its type enum in `KElsterTable.h`. Per repo convention neither is copied
here.

**Everything the low conversations ask for is named, and the data agrees.**

| Answered by | Element | Name | Type | Value seen |
|---|---|---|---|---|
| 0x180 | 0x0003 | `SPEICHERSOLLTEMP` | dec | 50.0 |
| 0x180 | 0x000C | `AUSSENTEMP` | dec | 15.3, frozen |
| 0x180 | 0x000E | `SPEICHERISTTEMP` | dec | 48.6 → 50.5 |
| 0x180 | 0x0016 | `RUECKLAUFISTTEMP` | dec | 26.2 → 54.1 → 24.6 |
| 0x301 | 0x0004 | `VORLAUFSOLLTEMP` | dec | 25.0 |
| 0x480 | 0x0112 | `PROGRAMMSCHALTER` | mode | 2 |
| 0x480 | 0x0122–0x0126 | day, month, year, hour, minute | LE | the clock |
| 0x480 | 0xFDB6 | `IMPULSRATE` | LE | |
| 0x480 | 0xFDBF | `DYNAMIK` | LE | |
| 0x601 | 0x0052 | `BRENNER` | LE | written 0 |

`dec` is `et_dec_val`, tenths with negatives allowed — which is where the
tenths reading in this file comes from, now sourced rather than assumed.

**The names are corroborated, not merely looked up.** The tank setpoint reads
50.0 while the tank actual climbs 48.6 → 50.5 and the return rises to 54 and
decays again: that is one domestic hot water cycle, and four independently named
elements telling the same story. A wrong table would not produce that.

**Above 0xFE07 the table simply stops**, and that is exactly where the manager's
own traffic lives. Of the eleven elements 0x480 polls from 0x700, seven are
absent from the list entirely — 0xFE09, 0xFE0A, 0xFE1B, 0xFE1C, 0xFE1D, 0xFE1E,
0xFE4C — and the three 0xFDFx names it does carry are wrong for this machine:

| Element | Table says | Data says | Every |
|---|---|---|---|
| 0xFDF3 | `STATUS_MULTIFUNKTIONSAUSGANG` | 27.8 – 53.7, tracks the return within ~5 K | 5 s |
| 0xFDF4 | `MODE_MULTIFUNKTIONSAUSGANG` | **is the return temperature** | 5 s |
| 0xFDF5 | `ANTILEGIONELLEN_ZEITPUNKT` | 26.2 – 54.0, related but distinct | 5 s |
| 0xFE07 | `INFOBLOCK_6` | 0.0 or 5.2 – 5.9, switches with the compressor | 4 s |
| 0xFE09 | — | 13.9 – 15.9, slow | 10 s |
| 0xFE0A | — | 13.4 – 13.6, slower still | 5 s |
| 0xFE4C | — | 1.8, constant | 5 s |

**0xFDF4 is the return temperature, and that is measured rather than guessed.**
Against the 400 samples where both were readable it matches `RUECKLAUFISTTEMP`
with a median absolute difference of **0.0 K** and r = 0.98 — the same physical
value, read by a different node under a different index. A "Mode
Multifunktionsausgang" does not track a return temperature to a tenth of a
degree for two hours. The table's own header warns it is under construction and
that indices must be verified before production use; this is what that warning
looks like in practice.

## The compressor, found by elimination

An earlier version of this file said 0xFE07 and 0xFE1D switch between two states
together and called the pair the compressor. **They do not, and it is not.**
Reading the whole capture as a state machine rather than as two time series is
what corrected it — the two coincide in exactly one window out of three.

The capture holds four states. Ignore the two stall gaps and the machine visits
each of them once:

| | 0xFE1B | 0xFE1C | **0xFE1D** | **0xFE07** | flow / return | tank |
|---|---|---|---|---|---|---|
| 16:02, 17:27–17:42 | 100 | 100 | 1 | **0** | falling 52 → 47 | 50.4 |
| 16:42–17:12 | 0 | 0 | 1 | **57** | 27.8 / 24.1 | 47.5 |
| **17:17–17:22** | 0 | 100 | **98** | **52** | **52.7 / 53.6** | **49.2 → 49.8, rising** |
| 17:47–17:52 | 0 | 0 | 1 | **57** | 29.9 / 24.7 | 50.5 |

**0xFE1D is the compressor.** Its one on-window is the one where heat is
actually made: the tank climbs toward its 50.0 setpoint and flow and return sit
at 53–54. The manager commands 0 or 100 and the module reports 1 or 98 back, so
the reported value is a measurement of a commanded output rather than an echo.

**0xFE07 is on in three of the four states**, including two where nothing is
being heated and the return sits at 24 °C. It reads 0 or 51–59 and jitters by
one every few seconds, so it is measured rather than commanded. What it is not,
is the compressor.

**Neither is in the element list, so neither gets a scaling it has not earned.**
The tenths in this file come from `et_dec_val`; an element with no entry has no
type either, which is why 0xFE07 is published raw.

## 0xFE07 and 0xFE1B: a command and its consequence

0xFE1B is commanded 0 or 100 by the manager and echoed back exactly. Across the
818 samples where both are known within 30 s of each other:

| 0xFE1B | 0xFE07 zero | 0xFE07 non-zero |
|---|---|---|
| 0 | 1 | 467 |
| 100 | 347 | 3 |

That is 814 of 818 in agreement, and **the four exceptions are the interesting
part**: every one of them falls inside a transition.

**The transitions establish which way the arrow points.** An anti-correlation on
its own cannot say whether 0xFE1B drives 0xFE07, the reverse, or neither. Two
transitions in the capture are resolved finely enough to answer it, because
0xFE07 is polled every four seconds while 0xFE1B is written every twenty:

```
17:25:52  FE1B = 100 already reported      FE07 = 53
17:25:59                                   FE07 = 7
17:26:04                                   FE07 = 0
```

```
17:42:32  FE1B = 100                       FE07 = 0
17:42:34  FE1B commanded 0
17:42:39                                   FE07 = 59
17:42:44                                   FE07 = 56      settles at 56-57
```

0xFE1B changes first and 0xFE07 follows, taking about ten seconds each way. It
does not switch: it **coasts down through 7 to 0, and starts with an overshoot
to 59 before settling.** A computed flag does neither. This is something with
mass in it, measured while it spins up and down.

The third transition, at 16:39, orders the other way — but the node had been
stalled until 16:39:14 and the state changed while it was blind, so it says
nothing.

**And 0xFE07 has a load step.** With 0xFE1B off, the compressor's state splits
it cleanly in two, with no overlap between the ranges:

| Compressor | n | Mean | Range |
|---|---|---|---|
| off | 266 | 56.3 | 55 – 59 |
| **on** | 201 | **52.3** | 51 – 54 |

So 0xFE07 has three operating points — 0, about 56, and about 52 — and moves
between them with mechanical lag.

**What is established:** 0xFE1B commands something, 0xFE07 measures it, the
polarity is inverted, and the thing has inertia and a load-dependent operating
point. That is the behaviour of a pump or a flow, not of a status word.

**What is not:** which pump, and in what units. The inversion is the oddity —
commanding 0xFE1B *to* 100 is what stops it. That fits a blocking or diverting
output better than a run command, and it is the reason this is not being named
yet.

### 0xFE07 is named after all, and the panel advice was misdirected

[kr0ner/OneESP32ToRuleThemAll](https://github.com/kr0ner/OneESP32ToRuleThemAll)
carries a property table that reaches into the range Jürg Müller's list stops
short of, and it names three of the four unknowns on this bus:

```cpp
PROPERTY(VORLAUFISTTEMP,   0xfdf3, Type::et_dec_val);
PROPERTY(RUECKLAUFISTTEMP, 0xfdf4, Type::et_dec_val);
PROPERTY(FROSTSCHUTZ,      0xfe07, Type::et_dec_val);
```

**0xFDF4 is the return temperature — which this file had already proved from
the capture alone**, by correlating it against `RUECKLAUFISTTEMP` at 0x180 to a
median absolute difference of 0.0 K. A published table now says the same. That
is the strongest validation the correlation method has had, and it means the
same method can be trusted on the elements no table covers.

**0xFDF3 is the flow temperature**, which fits its measured behaviour exactly:
it tracked the return within about 5 K throughout, which is what a flow and a
return do.

**0xFE07 is `FROSTSCHUTZ`, in tenths — so 5.1 to 5.9 °C.** And that means the
advice this file gave after the panel search came up empty was wrong in a way
worth recording. The tenths reading *was* right; what was wrong was expecting a
frost protection limit to appear on the display at all. Telling the user to look
for "56 rather than 5.6" doubled down on the wrong half of the problem — the
scaling was never the issue, the assumption that an internal protection value is
a displayed measurement was.

**The behaviour still deserves a second look.** A protection limit that ramps
down through 0.7 °C, overshoots to 5.9 and jitters by a tenth every few seconds
is not obviously a static setpoint, and it steps from 5.6 to 5.2 when the
compressor runs. A computed limit tracking a filtered temperature would do all
of that, so the name and the dynamics can be reconciled — but the earlier
reading of "something with mass in it, so a pump or a flow" was over-confident
and is withdrawn.

**Still unnamed by any of the four sources: 0xFDF5, 0xFE09, 0xFE0A, 0xFE1B,
0xFE1C, 0xFE1D, 0xFE1E and 0xFE4C.** 0xFE1D remains the compressor by behaviour,
which no table contradicts.

### 0xFDF5 is the reheat's flow temperature, and the panel is what proved it

The list above is one shorter after the panel walk. The screen that named
`0x06A0` and `0x06A1` — MENOVIRT TOSILÄMPÖT NHZ and WP — was displayed while
both 0x700 elements were being polled, and the correspondence is exact at every
opportunity:

```
07:32:51  06A0 = 26.5   0xFDF5 = 26.5      07:32:51  06A1 = 26.3   0xFDF3 = 26.3
07:32:56  06A0 = 26.5   0xFDF5 = 26.5      07:33:01  06A1 = 26.3   0xFDF3 = 26.3
07:33:01  06A0 = 26.5   0xFDF5 = 26.5      07:33:09  06A1 = 26.3   0xFDF3 = 26.3
...                                        matched 9 of 9, 0.0 K every time
```

**`0xFDF5` is the flow temperature of the electric reheat**, and `0xFDF3` is the
heat pump's — which confirms `VORLAUFISTTEMP` from a source that owes nothing to
kr0ner's table. This is the third pair found the same way, after `0xFDF4` and
`0x0016` for the return, and the method has now been right every time it has
been checkable.

**The practical consequence is larger than a name.** Both 0x700 elements arrive
every five seconds whether or not anyone is at the panel, while `0x06A0` and
`0x06A1` arrive only during a walk. The flow temperature was never missing from
this bus; it was being logged continuously under an index nothing had named. The
entities follow the convention the return already set — `Flow temperature` for
the panel's copy, `Flow temperature (module)` for the one that is always there,
and the second is the one to build on.

### 0xFE07 keeps its raw name, and here is the standard being applied

`FROSTSCHUTZ` comes from kr0ner's table and nothing else. No screen in the walk
displayed a value matching it, the dynamics recorded above do not fit a static
protection limit, and this project's bar for renaming an element is a measured
correspondence — which is what `0xFDF4`, `0xFDF3` and now `0xFDF5` each have and
`0xFE07` does not. A borrowed name is a hypothesis; the entity keeps its index
until something on this machine agrees with it.

**And it produced an outlier worth recording.** During the walk `0xFE07`
published **1584** once, at 07:43:57 — against a lifetime range of 0 and 51 to
58 across eleven hours. That is 27 times the largest value ever seen from it.
Not a sentinel, so the guard did not catch it, and one sample is not a range
check: **a third class of bad data**, after the corrupted identifier and the
sentinel, and the only one this configuration currently has no answer for.

### 0xFE1B and 0xFE1C separate once the hydraulics are known

The tank is charged by the heat pump and the floor heating draws from that same
tank, through the tank's pump plus a separate small circulation pump. Two pumps,
and the capture commands exactly two outputs besides the compressor.

They are not interchangeable, and one table separates them:

| | Tank charge, compressor on | Floor circulation, compressor off |
|---|---|---|
| **0xFE1C** | **100** | **100** |
| **0xFE1B** | **0** | **100** |

**0xFE1C runs in both modes and 0xFE1B only in circulation.** Against the
plumbing that makes 0xFE1C the tank's own pump — needed whether heat is going in
or coming out — and 0xFE1B the separate circulation pump, which belongs to the
floor side alone.

An evening of idle running shows the pair cycling together with the compressor
never starting at all:

```
19:37  both on    54 min
20:31  both off   20 min
20:51  both on    44 min
21:35  both off   20 min
21:55  both on
```

Tank 49.8 → 47.1 °C across the whole of it. This file first read that as space
heating drawing the tank down. **It is not, and the rates disprove it.**

| Window | DHW tank | 0xFDF3 | 0xFDF5 |
|---|---|---|---|
| pumps on | −1.4 | −3.1 | −2.5 |
| pumps off | −1.7 | **+13.4** | **+5.8** |
| pumps on | −0.9 | −5.6 | −5.4 |
| pumps off | −0.3 | **+9.3** | **+6.9** |
| pumps on | −1.5 | −7.7 | −8.7 |

°C per hour. **The DHW tank falls at the same rate whether the pumps run or
not**, so nothing the pumps do touches it — that is standby loss and draw-off,
not space heating. The machine has two circuits, one for the DHW tank and one
for the floor's buffer, and this is the second one running while the first
quietly cools.

**0xFDF3, 0xFDF4 and 0xFDF5 all swing hard with the pumps** — down while
circulating, sharply up when it stops. Three sensors in the circulating path,
seeing the floor's cooler water while it moves and drifting up toward the
machine's own warmth when it stands still.

That rules something out. **None of the elements on this bus behaves like a
buffer tank.** A buffer being drawn from would fall while the pumps run and then
hold roughly flat when they stop; all three of these rebound instead, which is
pipework, not storage. Either the buffer has no sensor reporting here, or the
floor circuit is plumbed through the machine rather than through a tank the bus
knows about.

0xFE09 and 0xFE0A move by tenths through all of it, so they are outside this
path entirely — source side or ambient.

**It also closes the frost protection story.** 0xFE07 reads 0 whenever 0xFE1B is
running and 5.6 °C whenever it is not — frost protection armed exactly when the
floor circuit is standing still, which is exactly when a floor loop can freeze.
The anti-correlation that took a whole evening to characterise turns out to be
the plainest thing on the bus once the pipework is known.

**A prediction the night can test.** When the tank falls far enough to trigger a
charge, 0xFE1C should go to 100 alongside the compressor while 0xFE1B stays at
0. If both come on together, the split above is wrong.

kr0ner also refines two names this file took from elsewhere: 0x010E is
`STEIGUNG_HK1`, the slope for heating circuit 1 rather than a generic heating
curve, and 0x0005 is `RAUMSOLLTEMP_TAG`. Both are the same parameters under more
precise names.

**Pending config change**, not worth a re-flash mid-capture: `Element 0xFE07`
should become a temperature in tenths named for frost protection, and
`Element 0xFDF3` a flow temperature. The raw values are in the log either way.

### The panel was checked, and nothing reads 5.6 or 5.2

That was worth doing and it removes something — but note what it removes. **The
tenths were an assumption of this file's, never a finding.** 0xFE07 has no entry
in the element list and therefore no type, and `et_dec_val` was read across from
the elements that do have one. Looking for 5.6 tested that assumption, not the
element.

So the number to glance for is **56 falling to 52** — a percentage, most likely
a pump's — or possibly 0.56 and 0.52. The pattern to match is the ratio and the
zero, not the decimal point. And it may not be on the panel at all: these are
module-level values on the manager's own conversation with 0x700, and a display
has no obligation to show them.

### A second handle: 0xFE09 is in the same circuit

Worth more than another number hunt. 0xFE09 steps in lockstep with 0xFE07,
within seconds of it:

| | 0xFE07 | 0xFE09 |
|---|---|---|
| 0xFE1B = 100 | 0 | **14.0** |
| 0xFE1B = 0, compressor off | ~56 | **15.5** |
| 0xFE1B = 0, compressor on | ~52 | **15.9** |

At 17:26:04 0xFE07 reached zero and 0xFE09 fell to 14.0 eight seconds later; at
17:42 it climbed back the moment 0xFE07 restarted. **A temperature that moves
when a pump starts is a temperature in that pump's circuit** — with no flow the
sensor drifts toward its surroundings, with flow it reads the fluid.

That gives a target with a shape rather than a bare number: **a temperature
around 14–16 °C that jumps about 1.5 K when something starts.** Finding it on
the panel names the circuit, and naming the circuit names 0xFE07.

One thing it argues against: the compressor running moved 0xFE09 *up* by 0.4 K,
not down. Extracting heat from a source loop cools it by several degrees, so
whatever this circuit is, **it is probably not the brine side.**

### If the panel has nothing, the node can answer it

Flash the configuration and watch `Element 0xFE07` for a day or two. The capture
covers one hot water cycle and no space heating at all; a heating run puts the
diverter in its other position, and whether 0xFE07 keeps the same two operating
points across that is what separates a source-side circuit from a heating-side
one. That costs nothing but time, and the entity is already there.

**0x000C deserves a second look.** `AUSSENTEMP` sat at exactly 15.3 °C across
all 239 samples in two hours — not a tenth of movement. Either no outdoor sensor
feeds this bus or the value is a placeholder, and **that matters for this
project specifically**: heating curve control assumes the machine has a live
outdoor temperature to apply the curve to. Check it on the panel before building
anything on top of the curve.

**Answered by the overnight capture, and the sensor is live.** 3945 samples,
37 distinct values, falling monotonically from 15.0 °C at 19:00 to 11.4 °C at
06:00 — an ordinary night-time cooling curve, one tenth at a time. Two hours of
a settled afternoon is simply not long enough to distinguish a slow real signal
from a frozen one. **No panel check is needed and the curve has something to
apply itself to**, which removes the one prerequisite phase 2 could not have
worked around.

## The four elements the manager writes

These matter more than the reads, because **phase 2 has to imitate exactly this
traffic** and the frames are on record:

| Element | Values written | Every |
|---|---|---|
| 0xFE1B | 0, 100 | 20 s |
| 0xFE1C | 0, 8, 12, 100 | 20 s |
| 0xFE1D | 0, 100 | 10 s |
| 0xFE1E | 0, 1, 4, 5, 6, 7, 15 | 20 s |

**None of the four is in the element list**, so their meaning has to come from
behaviour. 0/100 reads as a percentage or an on/off actuator, and 0xFE1E's small
distinct set looks like a bitfield. 0xFE1D is the informative one: it switches
in step with 0xFE07, and the temperatures rise while both are on — so this
group is the manager commanding the compressor side, not configuration.

**An eleven-hour capture widens two of these rows and separates command from
report.** 0xFE1C gains an 8, written three times between 02:06 and 02:09 at the
tail of a long compressor run — rare, but it means a value set collected in two
hours is a floor and not a set. 0xFE1E gains 1 and 5 and **loses 3**: the value
3 is something 0x700 reports, never something 0x480 writes, and an earlier
reading of this table mixed the two directions. The distinction is not
cosmetic — phase 2 writes commands, so a table of "values written" that
contains a reported-only value would have it imitating a frame the manager
never sends.

**0xFE1E is a bitfield, and the machine's state is what sets the bits.** Over a
night its commanded value tracks the compressor closely enough to read from the
hourly histogram alone: 0 and 4 while idle, 7 and 15 while running. The hour
from 01:00 contains 67 writes of 7 and 125 of 15 and **not one 0 or 4**; the
quiet hours from 03:00 to 05:00 are the exact inverse. Bits 0 and 1 are the
ones that only come up with the compressor.

That is worth knowing before phase 2 borrows the pattern. **Copy the shape of
these frames, not their elements.** Each write is answered by 0x700 echoing the
value, so the write-then-verify handshake is the machine's own and phase 2
should imitate it rather than write blind — but the elements phase 2 wants are
setpoints and curve parameters, which live in the named low range, not here.

## 0x4E5E is a status word, and bit 9 is the compressor

**This element is not in the list, not in the two-hour capture's account, and
not in any implementation read for this file.** It surfaced only because the
manager writes it to 0x100 rather than to 0x700, so nothing claimed it and the
unclaimed-frame log printed it: 62 frames over eleven hours, 20:31 to 05:59, 17
distinct values.

The values are not a scale. Read as bits they are a machine state:

| Time | Value | Bits set | Compressor |
|---|---|---|---|
| 22:15:05 | 65 | 0, 6 | off |
| **22:16:13** | **577** | **0, 6, 9** | **on, same second** |
| 22:33:30 | 721 | 0, 4, 6, 7, 9 | on |
| 22:43:27 | 49 | 0, 4, 5 | on, 19 s before the sensor drops |
| 22:45:01 | 1 | 0 | off |
| **00:00:36** | **577** | **0, 6, 9** | **on, same second** |
| 00:28:12 | 753 | 0, 4, 5, 6, 7, 9 | on |
| 02:12:20 | 561 | 0, 4, 5, 9 | on |
| 02:14:15 | 1 | 0 | off |

**Bit 9 rises in the same second as the compressor on both starts.** Bit 0 is
set in every frame ever seen. Bits 4 to 7 move around inside a run. Bit 14
appears only in brief pairs — 16449, 16577, 17089, 17137 — each a few seconds
from an otherwise identical value without it, so it reads as a momentary flag
rather than a state.

**This is a better compressor signal than the one this configuration uses.**
0xFE1D is a command the manager issues and 0x700 answers, so the current sensor
infers a state from a commanded output polled every five seconds. 0x4E5E is a
single register that changes on the transition itself. On the first stop its
bit 9 cleared 19 s before the 0xFE1D-derived sensor did; the second stop has no
frame in the window that would resolve it, so **one observation is all there
is** and leading behaviour is not established. What is established is that the
bit and the compressor agree, and that four more bits of machine state are
sitting in a register nothing currently reads.

Worth a sensor before phase 2, and worth watching against the panel's own
status display — that is the cheap way to name bits 4 to 7.

## The four unclaimed elements that keep time

0x06AF, 0x1388, 0x080E and 0x019A are named elsewhere in this file as traffic
worth reading, but never timed. Eleven quiet hours give each of them a period,
and a period is the strongest clue any of them carries:

| Element | Direction | Median interval | Values |
|---|---|---|---|
| 0x06AF | 100 → 480 | **60 s** | always 1 |
| 0x1388 | 480 → 100 | **52 s** | 0, and 8246 exactly twice |
| 0x080E | 480 → 100 | **368 s** | 4, 6, 0 |
| 0x019A | 180 → 100 | **600 s** | always 10 |

**A constant on a fixed period is a heartbeat, not a measurement.** 0x06AF at
one a minute and 0x019A at one every ten are keepalives — 0x06AF from the panel
to the manager, 0x019A the boiler answering. Neither will ever be a sensor
worth having, and knowing that is what stops them being investigated again.

**0x080E's 368 s is the interesting number**, because it is the system-frame
burst period. Those bursts come round every seven minutes, and this element
rides with them rather than on a clock of its own.

**0x1388's two exceptions are the whole of its information.** It reads 0 in
every frame of the capture but two; both of those read 8246, and both fall
inside the twenty minutes someone was browsing the panel. Whatever it carries is a consequence of the
panel being touched, which makes it a menu-walk target rather than a background
one.

## The panel walk, and why it beats the element list

Six minutes of opening screens on the machine's own panel named **27 elements
to the digit**. That is more than two hours of passive capture produced, and it
is a better class of evidence than anything in this file so far: the element
list is a table someone else wrote about a family of machines, while a
photographed screen is this machine stating what it believes a number means.

**The method is cheap and worth repeating whenever something is unknown.**

1. Turn on `Log read requests`. On a screen the panel *asks* for every value it
   shows, and the request names the element even when the answer never arrives.
   The walk logged **771 read requests across 85 distinct elements**; the
   overnight capture, with reads suppressed, had seen 85 elements in total.
2. Photograph each screen. A phone stamps `exif:DateTimeOriginal` in local time
   while naming the file in UTC — the EXIF is what to trust, and it lines up
   with the ESPHome log to the second.
3. Intersect. For each photo take the frames between it and the next, and look
   for an element whose value matches a number on the screen and which is not
   also responding while a different screen is up.

Five of the fifteen screens are kept here as the evidence for the tables below
— stripped and resized by the pipeline in the repo's CLAUDE.md, because a phone
photograph carries GPS to a few metres and this repo is public:

| | |
|---|---|
| [`panel-info-heating.jpg`](panel-info-heating.jpg) | names 0x02CA, 0x06A0, 0x06A1 |
| [`panel-info-reheat.jpg`](panel-info-reheat.jpg) | the sentinel printed as POIS |
| [`panel-info-heat-quantity.jpg`](panel-info-heat-quantity.jpg) | the totals that turn out to be computed |
| [`panel-info-running-hours.jpg`](panel-info-running-hours.jpg) | five hour counters, all exact |
| [`panel-settings-heating-circuit-1.jpg`](panel-settings-heating-circuit-1.jpg) | the curve, which is what phase 2 is for |
| [`panel-diag-event-list.jpg`](panel-diag-event-list.jpg) | the event list, code 8246, and the table transfer it produced |
| [`panel-info-heat-quantity-page2.jpg`](panel-info-heat-quantity-page2.jpg) | NHZ LV SUMMA, the row that overturned the element verdict |

Ambiguity is real and shows up as two elements holding the same value. It is
resolved by finding a screen that shows one of them alone: `0x01AC` and
`0x01AD` both read −19.0, and the settings screen for the reheat asks only
`0x01AC`, which names it and leaves `0x01AD` to the other row by elimination.

### What the walk named

**Settings — the parameters phase 2 exists to write.** The first three are the
mixer module's, and **0x601 had no branch in the configuration at all** before
this: it answers nothing unless a screen asks it, so eleven hours of capture
never saw a single one of them.

| Element | From | Panel | Value |
|---|---|---|---|
| `0x0005` | 0x601 | MUKAV-LÄMPÖTILA | 26.0 °C |
| `0x0008` | 0x601 | ECO-LÄMPÖTILA | 23.0 °C |
| `0x010E` | 0x601 | LÄMMITYSKÄYRÄN NOUSU | 0.23 — the curve, `et_cent_val` confirmed |
| `0x0013` | 0x180 | LV MUKAV-LÄMPÖTILA | 55.0 °C |
| `0x0A06` | 0x180 | LV ECO-LÄMPÖTILA | 50.0 °C |
| `0x0028` | 0x180 | MAX PALUUVIRT LÄMPÖT | 50.0 °C |
| `0x01E8` | 0x180 | MAX MENOVIRT LÄMPÖT | 60.0 °C |
| `0x0A00` | 0x180 | JÄÄTYMISESTO | 4.0 °C |
| `0x068F` | 0x180 | PUSKURIKÄYTTÖ | PÄÄLLÄ (1) |

**Measurements.** `0x06A1` is the one that closes a gap: the return
temperature has been readable from two independent nodes since the first
capture, and **the flow temperature from none**.

| Element | Panel | Value |
|---|---|---|
| `0x06A1` | MENOVIRT TOSILÄMPÖT WP | 26.3 °C — flow, heat pump |
| `0x06A0` | MENOVIRT TOSILÄMPÖT NHZ | 26.5 °C — flow, reheat |
| `0x02CA` | TOSILÄMPÖT HK 1 | 25.4 °C |
| `0x01D4` | LÄHTEEN LÄMPÖT | 10.3 °C — brine |
| `0x01B0` | LÄHTEEN LÄMP MIN | −9.0 °C |
| `0x0675` | LÄHDEPAINE | 0.41 bar — **hundredths** |
| `0x0265` | KUUMAKAASULÄMPÖT | 25.4 °C |
| `0x0268` | PAINE KORKEAP | 10.7 bar — **tenths** |
| `0x07A5` | PAINE ALAPAINE | 10.3 bar — tenths |

**Two pressure scalings on one machine**, and only the panel separates them:
107 reads 10.7 bar and 41 reads 0.41 bar. From the numbers alone there is no
way to tell which is which, and a single scaling would be wrong by a factor of
ten somewhere.

**Running hours**, all five exact, all from 0x180: `0x07FC` = 2215 h compressor
heating, `0x0802` = 3530 h compressor DHW, `0x0259` = 134 h reheat stage 1,
`0x025A` = 132 h stage 2, `0x0805` = 5922 h both.

**Reheat switching**, and the pair that needed the elimination argument:
`0x01AC` KYTKENTÄLÄMPÖT HZG −19.0, `0x01AE` KÄYTTÖRAJA HZG POIS, `0x01AD`
KYTKENTÄLÄMPÖT WW −19.0, `0x01AF` KÄYTTÖRAJA WW POIS.

### The sentinel means POIS, which is not what this file said

The 0x9000 sentinel appears on three different screens — KÄYTTÖRAJA HZG,
KÄYTTÖRAJA WW, MINIMILÄMPÖTILA — and on every one of them **the panel prints
`POIS`**. It marks a function that is deliberately switched off, not a sensor
that is missing or a parameter that was never configured.

The practical difference is in diagnosis. "Not present" invites looking for a
detached sensor; the machine means the feature is off, and the place to change
it is the same screen. The guard in the YAML is unaffected — either way the
value must never reach a sensor — but a sentinel in the log is **not evidence
of a fault**.

### The panel's totals are computed, and the bus does not send them

Every energy counter arrives in pieces: a stored base as an MWh word and a kWh
word, plus a separate day counter. **The screen shows their sum**, and the bus
never sends that number.

```
0x0930/31 = 822 / 86  →  86 822 + 27  =  86.849 MWh   ✓ on screen
0x092C/2D = 969 / 18  →  18 969 +  3  =  18.972 MWh   ✓
0x091C/1D = 525 /  7  →   7 525 +  1  =   7.526 MWh   ✓
0x0920/21 = 135 / 18  →  18 135 +  6  =  18.141 MWh   ✓
```

Four counters, each to the kilowatt-hour. A configuration that published the
base alone would disagree with the machine's own display by up to a day's
production — small, plausible, and exactly the kind of discrepancy that gets
chased as a bug in the wrong place. So the handler assembles the same sum.

**The parts arrive in no fixed order**, which is a trap worth naming because
this file fell into it. The obvious implementation publishes on the MWh word,
reasoning that it comes last in ascending element order. On the very walk that
identified these elements `0x0921` arrived seven frames *before* `0x0920`, and
the total came out 135 kWh short. Each counter now marks which parts it has and
publishes only on a complete set.

**That bug was caught by replay, not by reading.** The decoded log carries
sender, command, element and value, which is everything needed to rebuild the
original seven bytes; 1669 frames reconstructed from the walk and pushed
through the handler on a host compiler reproduce **27 of the 27 values legible
on the photographs**, which is what makes the remaining two — `0x0022` and
`0x0263`, both reading 30 — legitimately open rather than merely unchecked.

```sh
g++ -std=gnu++17 -Wall -Wextra -o replay replay.cpp && ./replay
```

### Still open after the walk

- **`0x0022` and `0x0263` both read 30.** One is LÄMMINVESIK HYSTER 3.0 K, the
  other WW KORJAUS 3.0 °C. They answered together on every screen that asked
  for either, so nothing in this walk separates them. Changing one on the panel
  would.
- **`0xFDF7` = 263 from 0x700**, the same reading as `0x06A1`'s 26.3 °C flow
  temperature. Very likely the flow as the module reports it — the twin of what
  `0xFDF4` already does for the return — but it appeared exactly once and one
  sample names nothing.
- **The `POIS` rows on the two PERUSASETUS screens.** Too many candidates
  answering 0 or a sentinel, and several rows reading POIS at once.
- **`0x4E5E`'s bits.** The compressor was idle for the whole walk and the
  status word only changes on transition. Naming bits 4 to 7 needs a walk while
  the machine is running.
- **`0x01D5` was asked of 0x180 once, at 07:32:52, and never answered.** The
  only element in the capture that a node declined to respond to at all.

### The second walk: the commissioning menu, and a lead on 0xFE1B and 0xFE1C

A second walk covered the screens the first one missed — settings, diagnostics
and the commissioning menu rather than the info pages. Thirty elements appeared
that no capture had shown before. Six are named to the digit:

| Element | From | Panel | Value |
|---|---|---|---|
| `0x070A` | 0x180 | KÄY → LÄMMITYS, LÄMMPIIRIPUMP TEHO | 100 % |
| `0x070B` | 0x180 | KÄY → LÄMMINVESI, LV-PUMP TEHO | 100 % |
| `0x01A2` | 0x180 | KÄY → LÄMMITYS, HD-ANTURI MAX | 40.0 bar |
| `0x0668` | 0x480 | DIA → LÄMPÖP TILA, JÄLJ LEPOAIKA | 00 min |
| `0x0691` | 0x480 | DIA → SIS LASKELMA, AIKAVÄLI | counts continuously |
| `0x0692` | 0x480 | DIA → SIS LASKELMA, KYTKETYT VAIHEET | 01 |

`0x0691` is the one that names itself by behaviour: it ran 65 → 99 → 73 → 81
inside two minutes while the screen showed 76, so it is a free-running counter
and the exact frame it was photographed against does not matter.

**`0x0668` is the other half of "why is it not running".** The EVU block below
answers one case; the compressor's remaining minimum-off time answers the rest,
and between them a machine that is idle for a reason is distinguishable from one
that simply has no demand.

**And the commissioning menu is the first evidence that this machine describes
pumps as percentages.** `0xFE1B` and `0xFE1C` have been unnamed 0/100 outputs
since the first capture, with `0xFE1C` also modulating through 8 and 12 — which
is a strange set for anything except a pump. Two pump-power rows now exist on
the panel, both configured to 100 %. **That is a lead, not a finding**: both
read the same value, so nothing here says which command drives which pump, or
whether the connection exists at all. The test is to catch `0xFE1C` at 8 or 12
and read the machine's live pump display in the same minute.

**`0x0078` is a second index for `0x02CA`.** Both answered 254 while the panel
showed TOSILÄMPÖT HK 1 = 25.4 on the first walk, and both answered 265 against
26.5 on the second. Same node, same value, two indices — the third such pair
after the return and the flow, and the first where both come from 0x180.

### A fourth class of bad data: the element index gets corrupted too

Watching the log after the second walk turned up four elements from 0x700 that
no capture had shown. **Most of them are not elements.**

`0xFE0E` settles it. It answered **135** twice, at 09:11:18.849 and 09:11:19.846,
in the millisecond after **four consecutive reads of `0xFE0A`** — and `0xFE0A`
reads 13.5 °C, which is **135 raw**. The two indices differ by one bit
(`0xFE0A ^ 0xFE0E = 0x04`). Same value, one bit apart, arriving as the answer to
the other one's request: this is a real `0xFE0A` response wearing a corrupted
index.

That is the fourth way this bus produces something that is not data, after the
corrupted *sender* identifier, the sentinel, and the out-of-range value. The
first three are handled; this one is not, and deliberately so — a guard would
have to reject any element the manager did not just ask for, and that is exactly
the mechanism by which a genuinely new element would be found.

**Graded by what the evidence supports:**

| Element | Value | Reading |
|---|---|---|
| `0xFE0E` | 135 | **corruption, proven** — one bit from `0xFE0A`, value identical |
| `0xFDF7` | 263, 265, 267 | **corruption, very likely** — one bit from both `0xFDF3` and `0xFDF5`, and its values sit inside their range |
| `0xFDF6` | 4225 | probably corruption — one bit from `0xFDF4`, requested 29 ms earlier, but the value matches nothing |
| `0xFF4C` | 0 | probably corruption — one bit from `0xFE4C`, which was just read; value does not match |
| `0xFF0B` | 0x8000 | **probably real** — three separate occasions, always the same index and the same sentinel. Corruption does not reproduce a particular index and value three times |

**So `0xFDF7` is withdrawn as a candidate flow temperature.** It was recorded
above as a one-sample hypothesis on the strength of reading 263 while the flow
was 26.3 °C; the same reasoning now points at a mangled `0xFDF3` or `0xFDF5`,
both of which are one bit away and both of which read that value at the time.

**And it is a warning about the method.** Naming an element from a single sample
that happens to match a plausible value is exactly the mistake this class
produces. Two of the three pairs proven so far — the return and the flow — were
established over hundreds of samples. One sample is a coincidence waiting to be
written down.

#### The corruption has a shape, and it is in two adjacent bytes

Twenty-eight corrupted responses have now been seen from 0x700, and none of the
indices they carry was **ever requested** — zero read requests for the whole
`0xFFxx` family across every capture, with read logging on. A response answers a
request; an unrequested response is not protocol traffic. That alone settles it,
and it retires an earlier reading in this file that called `0xFF0B` "probably
real" because it recurred. The recurrence was the right observation and the
wrong conclusion.

**Three cases are proven by value, not by argument:**

| Seen | Is really | XOR | Evidence |
|---|---|---|---|
| `0xFE0E` = 135 | `0xFE0A` | `0x0004` | 0xFE0A reads 13.5 °C — 135 raw |
| `0xFE0F` = 0 | `0xFE07` | `0x0008` | 0xFE07 reads 0 when idle |
| `0xFF4C` = 18 | `0xFE4C` | `0x0100` | 0xFE4C is constant 18 |

**Every flipped bit lands in the low bits of the two index bytes.** The element
index is bytes 3 and 4 of the frame, so `0x0002`, `0x0004` and `0x0008` are the
low bits of byte 4 and `0x0100` is the lowest bit of byte 3 — two adjacent bytes,
bottom bits of each:

```
0x0002   1     0x0100   2      bit 8 alone
0x0004   6     0x0102  10      bit 8 with a low bit
0x0008   3     0x0104   3
0x022C   3  ← the one that fits nothing
```

Fifteen of the twenty-eight involve bit 8. This is not uniform noise across the
frame, and a pattern that concentrated points at sampling or timing in the read
path rather than at the wire. **It is a shape, not yet a diagnosis** — one more
capture that keeps it would make it one.

**The rate is a floor, not a measurement, and that is the important caveat.**
Only corruptions that land *outside* the known element set are visible: a flipped
bit that turns one real index into another real index is delivered, published,
and indistinguishable from data. The 0x700 poll covers about eleven elements
every five seconds, so the denominator runs past a hundred thousand responses —
but the numerator counts only the ones that missed.

**Which is the argument for the guards, restated.** The sentinel guard and the
sender check catch what they catch because those values and identifiers are
impossible. Nothing makes a wrong-but-legal element index impossible, and the
median filter on the three fast temperatures is the only thing standing between
that class and Home Assistant's history.

**Still unnamed, and the evidence for them no longer exists:** `0x4E5A`,
`0x06AE`, `0xFDAE`, `0xFDB0`, `0xFDB1`, `0xFDC0`, `0x070E`, `0x070F`, `0x0030`,
`0x0669`, `0x1710`–`0x1712`, and the weekly-programme block `0x011B`–`0x0120`.
Most answer 0 or a sentinel, which is why they were not worth the photographs
that have since been deleted. `0x0673` is the exception worth a second look: it
read 0 on the first walk and 2899 then 2952 within seconds on the second, so it
moves fast and is not a setting. Naming any of these needs a fresh walk.

### 0x1388 is the status code, and 8246 is the utility block

The second walk opened DIAGNOSTIIKKA → VIRHELUETTELO, and the panel dumped the
list onto the bus in a form nothing else on this machine uses: **an indexed
table transfer.** `0x0B9A` counts rows, 0x480 increments it and 0x100
acknowledges each one, and six fields follow per row.

| Element | Field |
|---|---|
| `0x0B9A` | row index, 0 upward |
| `0x0B9B` | code |
| `0x0B9F` `0x0BA0` `0x0BA1` `0x0BA2` `0x0BA3` | minute, hour, day, month, year |

Twelve rows decoded, every one in strictly descending time order, and the screen
confirms the first two exactly — `01. 8246 / 19:53 05.SYY 26` against index 0's
53, 19, 5, 9, 26. This is the only tabular transfer seen on this bus; everything
else is single values.

**All twelve rows carry the same code, and the code is not a fault.** 8246 is
the EVU block — the machine's load-control input — and the panel files it under
VIRHELUETTELO because that is the only list it has, not because anything is
wrong.

**The block is this installation's own doing, not the grid operator's.** Home
Assistant drives the EVU input from the spot price, to keep the compressor off
during the expensive hours. That is confirmed by the owner and the log agrees:
the twelve entries are not a fixed schedule but a varying one — two on some
days, one on others, and **none at all on 29 and 30 August**. A utility's
contracted block would not skip two days; a price threshold would, on a cheap
one.

**Which makes the entity a confirmation loop rather than a discovery.** Home
Assistant already knows when it asked for a block; what it has never had is the
machine's own report that the block arrived and took effect. Those are different
facts, and only the second one says the wiring works.

**And it is a second control path to keep in mind for phase 2.** This machine is
already being load-controlled from Home Assistant over the EVU contact. Curve
control over CAN would be a second hand on the same machine, and the two can
disagree — writing a setpoint during a block achieves nothing, and a block
arriving mid-write is not something the bus will announce.

**One block was captured whole**, and it makes `0x1388` legible:

```
19:53:22   1388 = 8246      block begins
19:55:50   1388 = 8246
20:01:58   1388 = 0         over
```

The register returns to zero, so it is a live status word and not a latched log
entry. The compressor stayed idle throughout; the night's first run was at
22:16.

**But it does not span the block, and the arithmetic settles it.** The EVU input
on this installation is configured with a 10-minute delay on and 20 minutes off,
so **no block can be shorter than 20 minutes**. The register is written every 52
seconds with no gaps — 211 writes across the night — and it read 8246 for at
most **13 minutes 5 seconds**, bounded by a 0 at 19:48:51 and the next 0 at
20:01:58. A code that has cleared while the block is still running is not the
block's state.

So the entity is named `EVU signal` and **the latching belongs in Home
Assistant**, which knows its own delays. Putting a 20-minute timer in the
firmware would bake one installation's automation settings into a heat pump
reader and be wrong the day they change.

**Which of the two edges 8246 marks is still open.** It could show while the
10-minute on-delay runs, or from the moment the block engages until some display
timeout. The capture cannot separate them: the compressor would not have run in
that window under either reading, so its behaviour says nothing. Catching a
block while the machine wants to run would decide it in one observation.

**This is the most useful single entity found on this bus.** Nothing else
distinguishes "no demand" from "forbidden to run", and the two look identical
from every temperature and every output. Phase 2 has to respect it: a write
during a block is at best ignored.

**An earlier reading of this file said 0x1388's two 8246 samples belonged to the
panel being browsed.** They did not — they are the block, which happened to
overlap the browsing. **And `0x080E` does not track it either**, which this file
also briefly claimed: it moves between 0, 4 and 6 all night, at 21:12, 22:29,
22:35, 22:36, 23:38 and so on, with no block anywhere near. It is something
else, probably an operating state, and it stays unnamed.

### Walking the menus costs data, and the price is now measured

The walk tripped the overflow watchdog **twice**, at 07:40:15 and 07:42:39 —
against once in eleven hours of ordinary running. Both times the node was back
in 16 seconds and `boot_is_good_after: 15s` marked the boot good, so safe mode
was never in play, and **`RESTORE_DEFAULT_OFF` did the job it was added for**:
read logging survived both restarts and the walk continued. `ALWAYS_OFF` would
have switched it off silently in the middle.

It also produced the first bad *values* this project has seen. Three samples,
all inside the walk:

```
07:34:52  Element 0xFDF5               0.0 °C     between two 26 °C readings
07:41:17  Return temperature (module)  0.0 °C
07:43:57  Element 0xFE07               1584       lifetime range is 0 and 51-58
```

| | Samples | Implausible |
|---|---|---|
| Overnight, reads off, 11 h | 14 079 | **0** |
| Walk, reads on, 47 min | 1 584 | **3** |

Two of the three fall between the two restarts. **This is receiver stress, not
the bus** — the same pattern as the `0xFB` frames of the first capture, which
also arrived seconds from a stall. It is a third class of bad data after the
corrupted identifier and the sentinel, and the only one that reaches a named
entity, so the three fast 0x700 temperatures now carry `median: window_size: 3`.
0xFE07 deliberately does not: its transition shape is the open evidence about
what it is, and a median would blunt exactly that.

**The obvious optimisation does not work, and the numbers are here so it is not
proposed again.** 79 % of read requests (912 of 1153) are the manager's own
five-second poll of 0x700, for elements this configuration already handles —
pure noise, and suppressing them looks free. Modelled against the capture:

```
peak     28 lines/s → 23 lines/s
average  3.44/s     → 2.91/s
```

Not enough, and the reason is structural: the manager's poll is spread evenly
across the whole walk, while the bursts that stall the receiver are the panel's
own — opening a screen dumps twenty-odd frames in one second, and logging those
is the entire point. **A menu walk cannot be logged without the bursts.** The
watchdog absorbing them is the design working, not failing.

## Three anomalies, all visible because the log falls back to raw hex

- **System frames do not use the request/response layout.** All 48 of them are
  `?? ?? FE 01 00 00 ??`, and 21 carry 0x79 in byte 1 — where a receiver's low
  bits belong. 0x79 is no address, and decoding it produces nodes that do not
  exist: 0x179, 0x379, 0x579. Everywhere else in the capture byte 1 is 0x00,
  the single exception being 0x601 legitimately addressing 0x301. The bursts
  come round every seven minutes.
- **Two frames carried 0xFB where the index marker belongs.** Both arrived in
  the same millisecond, seconds before a receive stall, and 0xFA → 0xFB is one
  bit. They are almost certainly corruption from the overflow rather than a
  second marker.
- **The short form's bytes 5–6 are not always zero.** 45 frames carry a small
  number in byte 6 — 44 of them 0x180 answering element 0x000E, one answering
  0x0003. The values are 1, 2, 3, 4, 6, 0x18 and 0x61, byte 5 is always zero,
  and none of it is in the documented layout.

The first two are logged raw by the configuration, and the third is shown as a
`+00XX` suffix. None of them would have been visible in a decoder that trusted
the layout.

### A second capture adds two more, and one of them is not corruption

Two and a half minutes of a later run produced two frames the first capture
never showed:

```
9A 00 FA FE 0A 00 87     from 0x700, command 10
C9 00 7D                 from 0x704, command 9, three bytes
```

**The second cannot be a mangled payload.** Both the identifier and the length
are covered by the CAN frame's own CRC, so a three-byte frame from 0x704 that
the controller accepted is a three-byte frame from 0x704. **0x704 is a node that
has never appeared before**, and a `dlc` of 3 is a telegram format this file has
not described at all. Whatever else it is, it is real.

That casts doubt on the reading of the first. `9A` is `92` with one bit flipped
and it carried the same element and value as a legitimate response two seconds
earlier, which is why corruption looked obvious. But commands 9 and 10 turning
up within minutes of each other suggests **a class of commands above 7 that this
capture simply has not seen enough of**, rather than two independent bit flips.

The overnight capture decides it, and the test is cheap: a command that recurs on
a schedule with sensible payloads is part of the protocol, while one that appears
in isolated bursts near a stall is damage.

**The first evidence says damage.** Both frames arrived while the node was
stalling every 26 to 77 seconds under the heavy logging. Once the load came off
and the node ran 22 minutes clean, 25 minutes of capture produced 26 raw frames
and **every one of them was an ordinary system frame** — no 0x704, no command 10.

That also answers the objection this file raised against itself. A `dlc` of 3
cannot be a corrupted payload because the CAN CRC covers the identifier and the
length — **but the CRC protects the wire, not the driver's buffer handling.**
When the MCP2515's receive buffers overflow and the driver loses track, it can
read stale or partial buffer contents and hand up a frame that was never on the
bus at all. The same explanation covers the 0xFB frames of the first capture,
which likewise arrived seconds before a stall.

So the leading reading is now that these are artefacts of the overflow bug
rather than traffic. A clean overnight run settles it: if a healthy node
produces none of them, they were never real.

```sh
grep " raw dlc=" wpc-night.log | awk '{print $NF, $0}' | sort | uniq -c
```

Either way the raw fallback is what surfaced them. A decoder that indexed a
command table by the nibble would have read past the end of it on the first
frame.

### The overnight run happened, and the overflow reading does not survive it

Eleven hours, some 95 000 frames, one watchdog restart at 20:00 and no other
interruption. The census above returns about 580 raw frames, and **all of them
but one are the ordinary system bursts. The exception is a single frame, and it
is the same frame:**

```
[21:47:22.946] 784 raw dlc=3  C9 00 7D
```

Byte for byte the payload of the earlier `C9 00 7D`, and the identifier is one
bit away from the 0x704 that carried it then — 0x704 against 0x784 is bit 7. It
arrived one hour and 47 minutes after the only restart, with the frame counter
incrementing normally on both sides of it, and no stall anywhere near.

**A stale buffer does not reproduce a three-byte payload byte for byte in two
separate runs.** So the overflow explanation fails on the evidence it was
supposed to be tested against, and the test this file set for itself has to be
read the other way: this frame is real traffic. Rare — twice in thirteen hours
of capture — but real, and command 9 with a `dlc` of 3 remains unexplained.

**What the night does establish is that the identifier is the field that gets
corrupted, not the payload.** It produced a second oddity, and this one decodes:

```
[22:19:42.949] 078 → 92 00 FA FE 1C 00 00
```

Seven bytes, a well-formed response to 0x480 for element 0xFE1C with value 0 —
which on this bus only 0x700 sends, and 0 is one of the two values 0x700 ever
reports for that element. But 0x078 cannot be a node: the scheme puts the
address in the high nibble and 0–3 in the low bits, so every real identifier is
a multiple of 0x080 plus 0–3. The payload survived intact and the identifier did
not, which is the exact inverse of the corrupted-payload reading.

**`LISTENONLY` is why either frame reaches the application.** The datasheet is
explicit, and it goes further than "no acknowledge":

> Listen-Only mode is a silent mode, meaning no messages will be transmitted
> while in this mode (including error flags or Acknowledge signals). In
> Listen-Only mode, both valid and invalid messages will be received, regardless
> of filters and masks… **The error counters are reset and deactivated in this
> state.**
>
> — MCP2515 data sheet DS20001801H, §10.3

A frame corrupted on the wire is normally destroyed by an error flag from some
node. This node sends none, and no other node's flag can un-receive a frame this
one has already latched. The last sentence is the one with consequences for
diagnosis: **the error counters cannot be consulted**, so garbage frames in the
log are the only corruption metric this configuration will ever have. Two
suspect identifiers in some 95 000 frames is the current reading, and the shape
check exists so that neither of them can be mistaken for a device.

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

**One `on_frame:` trigger, with `can_id_mask: 0x000`.** A zero mask matches
every identifier — this is a sniffer, so filtering is the opposite of what is
wanted. The second trigger that used to sit beside it watched for extended
identifiers; it stayed silent through the first capture, which is the proof it
existed to produce, so it is gone.

## The log decodes, it does not dump hex

The byte layout is confirmed (see "Prior art"), so the handler applies it rather
than printing raw bytes. Reading a capture then needs no mental arithmetic,
which matters because the next step is matching hundreds of element indices
against a published table.

```
100>180 rd    e=000C
180>100 resp  e=000C = 147 (0x0093)
480>700 rd   ex=FE4C
700>480 resp ex=FE4C = 18 (0x0012)
480>700 wr   ex=FE1B = 100 (0x0064)
```

Sender is the CAN identifier; receiver is decoded from bytes 0 and 1, so a
sub-addressed node appears as `301` rather than `300`. `e=` marks an element
index taken straight from byte 2 and `ex=` one behind the `FA` marker — the
distinction is kept visible because it is a protocol fact worth watching, not an
implementation detail. Values print signed, since temperatures below zero are
expected, with the raw hex beside them so nothing is lost to a scaling guess.

Three decisions keep the decoder honest rather than merely convenient:

- **A read request prints no value.** Its last bytes are padding, and showing
  them would put numbers in the log that were never on the bus.
- **The short form's spare bytes 5–6 are shown if they are ever non-zero**, as a
  `+ABCD` suffix. Every captured frame had them at zero; if that assumption is
  wrong somewhere, the log says so instead of dropping the bytes.
- **Anything that does not fit the shape falls back to raw hex** — a length
  other than 7, or a command nibble above 7, which is where the large-telegram
  commands 0x20/0x21 would land. A decoder that mis-decodes silently is worse
  than no decoder.

The logic was run against every frame recorded in this file before flashing, on
a host compiler, including the negative value, the sub-address and both
fallbacks. That checks the arithmetic; it does not check ESPHome's schema, which
still needs a validate.

**The `CAN frames` counter** answers "is the bit rate right?" without reading
the log at all: it stays at zero on a wrong rate and climbs steadily on a
correct one. That is worth an entity of its own during a sweep that may take
several re-flashes.

## The sensors, and why they are publish-only

Eleven entities and a switch: seven for the elements the element list named,
four more from 0x700 that it does not reach, and `Log every frame` to turn
per-frame logging back on when raw frames are wanted. **Not yet validated or flashed** — the reasoning
below is checked against the capture, not against a running node.

Every one of them is `update_interval: never` with no lambda: the frame handler
pushes into them as values arrive. Polling a template sensor would invent an
update rate the bus does not have, and the bus already publishes faster than
Home Assistant needs.

**The dispatch matches on sender *and* element**, never on the element alone.
That is the one structural lesson of the naming work: 0xFDF4 read from 0x700 is
a return temperature, and the published list's name for that same index is
something else entirely. An index without a device is not an identifier.

| Entity | From | Element | Updates |
|---|---|---|---|
| Return temperature | 0x180 | 0x0016 | every 10 s |
| DHW tank temperature | 0x180 | 0x000E | every 10 s |
| Outdoor temperature | 0x180 | 0x000C | every 10 s |
| DHW setpoint | 0x180 | 0x0003 | **when something asks** |
| Flow setpoint | 0x301 | 0x0004 | **when something asks** |
| Operating mode | 0x480 | 0x0112 | occasionally |
| Heat pump clock | 0x480 | 0x0122–0x0126 | every minute |

The two setpoints were each asked for exactly once in two hours, so they stay
unknown until the bus asks again. **That is a property of the bus, not a bug**,
and it is worth knowing before wondering why an entity is empty. Nothing here
polls for them, because polling means transmitting and phase 1 does not.

**The clock is assembled, not read.** Five elements arrive separately; only the
minute arrives every minute, so the minute triggers the publish and the rest are
cached. Two guards keep it honest: nothing is published until a real date has
been seen, and a reading that is not a valid date is dropped rather than shown.
A rejected reading costs one minute, because every part is refreshed the next
time the panel polls.

**Two more entities come from 0x700, which the element list does not reach.**
They are named from behaviour instead, and named only as far as the behaviour
goes — see "The compressor, found by elimination":

| Entity | From | Element | Kind |
|---|---|---|---|
| Compressor | 0x700 | 0xFE1D | binary, on above 50 |
| Element 0xFE07 | 0x700 | 0xFE07 | raw integer, diagnostic |
| Element 0xFE1B | 0x700 | 0xFE1B | raw integer, diagnostic |
| Element 0xFE1C | 0x700 | 0xFE1C | raw integer, diagnostic |

0xFE1B is here because it is the command whose consequence 0xFE07 measures,
and identifying either needs both visible. 0xFE1C modulates between 0, 8, 12
and 100 and is the only other output that moves at all.

`Compressor` is binary because 0 and 100 are the only commands in the capture.
If an intermediate value ever appears, this wants to become a percentage.
`Element 0xFE07` carries no unit, no device class and no scaling, because none
of the three is known — publishing it raw is what makes it identifiable later,
and watching it in Home Assistant against the temperatures is the cheapest way
to find out what it is. Rename it the day it is identified.

Replaying the capture through the handler on a host compiler produced 239 return
temperatures, 228 tank temperatures, one of each setpoint, `Automatic` for the
mode, 72 compressor-on samples against 196 off, and a clock running from
`2026-09-05 18:01` to `18:07` while the capture itself ended at 17:56 — the
eleven-minute drift, arrived at a third time and by a different route.

Left out on purpose: `IMPULSRATE`, `DYNAMIK` and `BRENNER` are named in the list
but appeared once or twice in two hours with no verified meaning here, and an
entity that is unknown forever is noise. 0xFE1B and 0xFE1C are left out for the
opposite reason — they are commanded outputs whose behaviour is clear enough to
be interesting but not clear enough to name, and 0xFE1B is the anti-correlation
that will probably identify 0xFE07.

## The silent stall: an overflow flag that never clears

**Observed 2026-09-05.** Frames arrived normally, the counter reached 269, and
then reception stopped permanently. The node stayed online, the log stayed clean,
`canbus` was not marked failed, and working the heat pump's panel produced
nothing. A restart brought traffic straight back.

The cause is the MCP2515's receive path. When both receive buffers fill, the chip
sets an overflow flag in `EFLG` — and if the driver never clears it, the buffer
stays marked full and **no further frame is ever accepted**. The earlier burst of
`receive buffer overrun` messages was the warning; the stall is what follows.

What makes it dangerous is that it is invisible. A stalled node and a genuinely
quiet bus look identical from the outside. During an overnight capture the
difference matters: one is a night of data, the other is a night of nothing.

Two mitigations are in the configuration:

- **Keep the loop quick**, which is why `logger` runs at INFO rather than DEBUG.
  Overruns are what set the flag in the first place.
- **A watchdog restarts the node** if the frame counter has not moved for two
  minutes, and logs a warning when it does. There is also a `Restart` button
  exposed in Home Assistant for the manual case.

### The window has been wrong twice, and for the same reason

Thirty minutes was a guess. Two minutes was measured — against a capture that
turned out not to be representative. A later run stalled **after 26 to 77
seconds of operation**, not once in half an hour, and the arithmetic inverted:
150 seconds dead for every 26 alive, about 70 % lost.

**The lesson is the rule, not the number: the window has to be shorter than the
fault is frequent.** Both earlier values were set from how long a stall lasted
rather than from how often one arrives, and only the second of those is under
this configuration's control. Twenty seconds keeps a fourfold margin over the
worst natural gap of 4.7 s, which is the one figure here that has never moved.

**Both changes were measured, and they fixed different things.** With per-frame
logging off the node ran **22 minutes** before its first stall instead of 26 to
77 seconds, and the tightened window cost **41 seconds** to recover instead of
150:

| | Between stalls | Lost per stall | Alive |
|---|---|---|---|
| Full logging, 2 min window | 26–77 s | 150 s | ~30 % |
| Logging off, 20 s window | 22 min | 41 s | ~97 % |

The lighter loop is what made stalls rare; the shorter window is what made them
cheap. Neither alone would have done it.

**Frequent restarts bring their own trap.** `boot_is_good_after` defaults to one
minute, so a node that runs 26 seconds and restarts never resets the boot loop
counter — after ten of those it comes up in **safe mode, with no canbus
component at all**, silently, for the rest of the night. The configuration now
sets it to 15 s, below the watchdog's own window, so a node that is merely being
restarted always counts as having booted.

**The cause is still unknown, and this run argues against the earlier theory.**
The first capture blamed a slow loop filling both receive buffers, on the
evidence of `receive buffer overrun` bursts and seven `canbus took a long time`
warnings. The later run produced **neither**, and stalled far sooner. Whatever
wedges the receiver, it is not visibly starving the loop.

What did change is what the node is asked to do: nine entities, and the same
per-frame logging. **Per-frame logging is now off by default** — four log lines
a second, serialised and encrypted over the API, is the largest thing in the
loop and the easiest to remove, and the data an overnight run actually needs
travels as entity publishes instead. A `Log every frame` switch turns it back on
for a minute when raw frames are wanted. The raw-hex fallback is never gated:
those frames are rare and they are the whole reason 0x704 was ever seen.

**The stalls stopped.** Five minutes, 29 counter samples, not one of them
static, 221 frames a minute and a single boot line. The previous firmware had
never managed 77 seconds. So the logging load was the cause and the first
capture's explanation was right after all — the missing `overrun` warnings
argued against it and were wrong.

### Silence and blindness are not the same thing

Turning per-frame logging off hid every element that has no entity, which on the
one night designed to catch a heating cycle is exactly backwards: **a new state
is where new registers appear.** The handler therefore tracks whether any branch
claimed a frame, and logs the ones nothing claimed.

That inverts what the log is for. It stops being a transcript and becomes an
exception report — the frames worth a human's attention are the ones this
configuration did not expect.

| | Lines per minute |
|---|---|
| Every frame, which stalled the node | 236 |
| Entity publishes alone | ~42 |
| Unclaimed frames only | **21** |

Read requests are excluded: they carry no value, they are 44 % of all traffic,
and a new element's *response* is logged anyway, which is where the data is.
0xFE4C answered 18 in all 683 samples, so it gets neither an entity nor 683 log
lines — but claiming it silently would mean never learning that it moved, which
is the one thing about it worth knowing. It is claimed while it repeats and
released to the unclaimed path the moment it does not, which costs one line per
distinct value ever seen.

**That mechanism has a blind spot, and eleven hours of capture is what shows
it.** The night produced zero 0xFE4C lines. Two different things produce zero
lines: the element held its value for eleven hours, or 0x700 stopped answering
it altogether — and **silence cannot tell them apart**, because the design
speaks only on change and "gone" is not a change. The same hole applies to
anything else claimed this way.

It is a real gap and it is deliberately still open. Distinguishing the two
wants a last-seen timestamp or a sighting counter, and a counter for a constant
is the entity this scheme exists to avoid; the honest fix is probably a
staleness check in the existing ten-second interval rather than a new sensor.
Nothing on this bus depends on 0xFE4C today, so it is not worth carrying an
untested change into a flash for. **Worth knowing before trusting a quiet log**:
here, quiet means unchanged *or* absent.

What is left is genuinely worth reading: the manager's four commanded outputs,
0x06AF and 0x1388 and 0x080E, the 0x011A responses, and every system frame.

### It is not a one-off, and the first window was far too long

The two-hour capture stalled **twice**, and the watchdog recovered it both
times. It worked exactly as designed and still lost most of the capture: the
node was dead for **69 of its 113 minutes**, because each stall cost the full
30-minute window plus the reboot.

The same capture measured what the window should be. Gaps between frames fall
into two groups with nothing between them:

| Gap | Count | What it is |
|---|---|---|
| ≤ 4.7 s | every other gap | the bus's normal rhythm |
| 2069 s, 2076 s | 2 | the watchdog's own 30-minute window plus reboot |

**Two minutes** therefore sits 25× above the worst healthy gap and cuts a
stall's cost from 35 minutes to two. Restarting that often does not trip safe
mode either — `boot_is_good_after` defaults to one minute, so a two-minute
uptime resets the boot loop counter, which the capture's log confirms it did.

This is a bandage on a driver bug, not a fix. Clearing `EFLG` is the component's
job, and if a later ESPHome does it, the watchdog becomes dead weight. Check the
warning count before deciding it has: **a healthy node logs no restarts at all.**

## Running an overnight capture

The first capture lost 69 of its 113 minutes and nobody knew until it was
analysed afterwards. A night is twelve hours of the same risk, so it is worth
five minutes of checking first.

**Verify before leaving it.** Watch the first few minutes after flashing:

- `canbus is marked FAILED` must be absent — that is the SPI signature, and it
  means the capture is worthless before it starts
- `CAN frames` must be climbing
- The new entities must populate. Return temperature, tank temperature and
  `Element 0xFE07` all arrive within ten seconds; the compressor within twenty.
  The two setpoints and the clock will not — see "The sensors" for why
- No repeated `Restarting device`. One restart every two minutes means the
  watchdog is firing, not that the bus is quiet

**One API client, and count them before starting.** The ESP8266 does not carry
three encrypted API connections, and the failure looks nothing like a resource
problem:

```
Successfully connected to wpc-can @ 192.168.1.41 in 0.009s
Can't connect to ESPHome API: The connection dropped immediately after
encrypted hello; Try enabling encryption on the device or turning off
encryption on the client (EncryptionHelloAPIError)
```

The message points at encryption and the key is fine — the same client with the
same key worked minutes earlier, and a wrong key fails every time rather than
suddenly. Three things hold connections open, and all three are easy to forget:
a **log tab open in the ESPHome dashboard**, an **earlier `esphome logs` still
running** (`pgrep -af "esphome logs"`), and **Home Assistant's own ESPHome
integration**.

**Home Assistant is not needed for a capture night**, which resolves the
contention rather than working around it. Entity values travel in the log stream
as `[S][sensor]` lines, so one detached log process carries both the raw frames
and the decoded entities — and it is the one connection the node comfortably
holds.

**The log survives the watchdog.** In the first capture the node restarted twice
and `esphome logs` reconnected and carried on both times, so restarts fragment
the data but do not end the capture. Counting the warnings afterwards is how the
stall rate gets measured:

```sh
grep -c "restarting to clear" wpc-night.log
```

**A quiet night is now diagnostic rather than ambiguous.** The bus polls itself
every five seconds, so a gap of more than a minute is a stall or a lost log
connection — never an idle machine. That was not true before the first capture,
and it is what makes an unattended run worth doing at all.

**Design the night, do not just leave it running.** The first capture caught one
hot water cycle and no space heating, which is exactly the gap that 0xFE07's
identification needs filled. In September the heating curve may well not call
for heat at all overnight, in which case the night produces a second hot water
cycle and answers nothing new.

If the aim is to separate a source-side circuit from a heating-side one,
**raise the room setpoint on the panel before leaving** so that a heating run
certainly happens. It costs a little energy and it buys the one state the
capture is missing.

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

**Passed on the bench:** with the six jumpers in place the FAILED line
disappears and only `config standard id=0x000` remains. SPI is proven, so any
silence on the bus from here on belongs to the bus side.

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

Done: the tap point (X27 on board A2), the bit rate, the byte layout, a
two-hour capture, the address census, and the discovery that the bus polls
itself. **Phase 1 can be finished passively** — the node never has to transmit
to see the numbers it wants, which was the open question and is now closed.

The element list has been matched: everything the low conversations carry is
named, and the manager's own 0xFDxx/0xFExx range is not in the list at all. What
is left:

- **Name the 0x700 range from behaviour, since the table cannot.** Seven of the
  eleven elements are absent and three more are misnamed. 0xFDF4 is already
  settled by correlation; the same method should reach 0xFDF3 and 0xFDF5 once a
  capture spans a heating cycle as well as a hot water one.
- **Check whether `AUSSENTEMP` is a live sensor.** It never moved in two hours,
  and heating curve control depends on it.
- **Explain 0x100.** It is not in the published address table, yet it is one of
  the two busiest talkers on this machine.
- **Validate and flash the sensors.** Eleven entities are written and checked
  against the capture on a host compiler, but not against ESPHome's schema and
  not on the node. Check the flash and RAM figures while doing it — the sniffer
  alone was 45.2 % and 40.0 %.
- **Re-capture once the watchdog window is two minutes**, to confirm the stall
  rate against a capture that is not two-thirds dead.

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
- ✅ 120 Ω resistor (not used at first — the bus measured 150 Ω, i.e. unterminated,
  so termination is an open question rather than a settled no)

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

## Rejected: ESP32 built-in CAN (esp32_can) — and the rejection now needs re-testing

**A working project runs this exact bus on stock `esp32_can` at 20 kbps.**
[Oggy512/ESP32-THZ504-Controller](https://github.com/Oggy512/ESP32-THZ504-Controller)
drives a Tecalor THZ 504 — same Elster protocol, same 20 kbps — with:

```yaml
canbus:
  - platform: esp32_can
    bit_rate: 20kbps
```

No `external_components`, no patched fork: its `esphome: includes:` pulls in C++
headers only, so the CAN layer is ESPHome's own. The rejection below was tested
on **2026.7.4** and the installed version is now **2026.8.2**, which is exactly
the upgrade the note said would reopen the question.

**If it validates, the whole MCP2515 goes away** — and with it the SPI wiring,
the pin lift, the crystal question, and the receive-stall bug that has cost this
project more time than everything else combined. The stall is an MCP2515 driver
problem; the ESP32's TWAI controller does not have it. The transceiver would be
the SN65HVD230 already chosen for phase 2, which is also the part that project
uses.

The re-test costs nothing and needs no hardware. **The file lives here** —
[`cantest.yaml`](cantest.yaml) — because the first time this instruction was
followed it failed on a missing file: the original was a throwaway and an
instruction to run a file nobody kept is not a procedure.

```sh
podman exec esphome esphome config /config/cantest.yaml
```

Copy it into the ESPHome container's `/config` first, or point the command at
wherever this repo is mounted. It is validation only — never flashed, drives no
hardware, and its pins are placeholders.

**Do that before ordering or soldering anything for phase 2.** Everything below
this line was true on 2026.7.4 and is kept because the reasoning still holds if
the re-test fails.

### The original finding, on ESPHome 2026.7.4

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

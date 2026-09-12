# Enervent Pegasos Eco ECE → Home Assistant (ESPHome) Integration Notes

> **Technical details and reasoning.** Overview: [README.md](README.md).

## Goal

Integrate an Enervent Pegasos Eco ECE ventilation unit with Home Assistant using a local ESPHome bridge over RS-485/Modbus.

## Current Environment

- Home Assistant running in Podman
- Enervent Pegasos Eco ECE ventilation unit
- RJ11 service connector available
- Suspected communication protocol: RS-485 (Modbus RTU)

## Hardware

### Required

- ESP32 development board (recommended over ESP8266) — in stock
- RS-485 ↔ TTL module — in stock: JZK, 5 pcs, automatic hardware flow control,
  works at 3.3 V or 5 V. See the wiring section: it is not a plain MAX485
  breakout and is wired differently
- **4P4C cable** — **not in stock, the one thing this project is waiting for.**
  This file said RJ11 until the connector was looked at; see below, and count
  the positions before ordering

### Optional

- A breakout adapter (not required if you are willing to cut one end of the
  cable). Note that an *RJ11* breakout will not fit a 4P4C jack

## The connector is 4P4C, not RJ11 — and that is a purchase, not a detail

The Freeway port on the Enervent computer board takes a **4P4C** cable, also
sold as RJ10 or a telephone *handset* cord: four positions, four conductors.
**A six-position RJ11 plug does not fit a four-position jack**, so an RJ11 cable
and an RJ11 breakout are both the wrong part.

This file said RJ11 from the first commit. What changed it: an independent
project documents the Freeway port as 4P4C, and **the connector on this unit
looks like the smaller one** when compared against a cable. That is an
observation and not a measurement — settle it by counting the metal contacts in
the jack, or by holding a handset cord (4P4C) against a wall-phone cord (6P)
and seeing which one matches.

| PIN | Colour | Signal |
|---|---|---|
| 1 | black | **+5 VDC** |
| 2 | red | Data + → module A |
| 3 | green | Data − → module B |
| 4 | yellow | Ground |

**Pin 1 is a supply and must not reach the transceiver.** That is the warning
this file already carried, now with a pin number on it. It is also an
opportunity, and the section below works out what that opportunity is actually
worth. The same reasoning is gone through for a bus supply in
[`../stiebel.eltron/CLAUDE.md`](../stiebel.eltron/CLAUDE.md).

### Powering the ESP32 from pin 1 — worth doing, worth doing last

This file used to offer two reasons for taking the node's supply from the
service port: no second supply, and a common ground reference. **The second
one is not a reason.** The common reference comes from pin 4, the yellow
conductor, and it is connected whether or not the 5 V is used. Once the unit's
ground, the module's ground and the ESP32's ground are one net, the reference
is already shared.

So the benefit is exactly one: **one cable carries both power and data**, and
the manifold-cupboard problem of needing a socket where the node lives goes
away. That is a real benefit for a permanent install and no benefit at all
during bring-up.

**Measure the rail before designing around it, and do not trust the number in
the table.** This repo has a fresh precedent: the Stiebel wiring diagram
labels X27 pin 4 `+12V` and it **measures 17.4 V** — an unregulated rail rises
above nominal at light load. If this one is genuinely 5 V it goes to the
ESP32's `VIN`, never to `3V3`, because the DevKit's own regulator belongs in
between. If it turns out higher, `VIN` will still take it, but the arithmetic
changes.

**What decides it is whether the rail can carry the peaks.** An ESP32 averages
around 100 mA and reaches 250–500 mA on Wi-Fi transmit bursts. A service port's
5 V is sized for a handheld tool or a small display, which could mean 100 mA
or 500 mA, and nothing in any document says which.

**The danger is not damage, it is diagnosis.** A sagging rail makes the node
reboot or behave erratically, and that is indistinguishable from Modbus not
working. Combining the two unknowns is how a week gets spent on the wrong one.
Hence the order:

1. Get the bus answering on a **separate USB supply**. Proven first.
2. Measure the rail unloaded.
3. Connect the ESP32 and measure again **during Wi-Fi traffic**. Below about
   4.7 V the rail cannot carry it. A multimeter averages and will miss the
   peaks, but a real sag shows up even so.
4. Only then make it permanent.

**Fuse the feed.** A polyfuse of 200–300 mA in the +5 V conductor keeps a fault
in this node out of the ventilation unit's control board. That is the same
condition the stiebel file puts on taking power from the heat pump's bus, and
it costs cents.

One more reason to buy a straight cable rather than a coiled handset cord:
4P4C conductors are around 28 AWG, which carries a few hundred milliamps over
two metres without trouble — but tinsel wire does not.

**Do not trust pin numbers through the cable — trust colours, then verify with
a meter.** A standard handset cord is *reversed*: pin 1 at one end lands on
pin 4 at the other. Cut one end, identify the four conductors by colour, and
then check with a meter which colour actually reaches which contact at the
surviving plug. A cord that happens to be wired straight-through and one that
is reversed look identical from the outside.

**Two independent things are still unverified for this unit.** The pinout above
comes from a project that confirms Pingvin, Pandion, Pelican and LTR-3 — **not
Pegasos**. And the wire colours are the convention for 4P4C cordage, not a
promise about this cable. Both are hypotheses to check with a meter, which is
the same standard this repo applies to every table it has had to overturn.

## Sources for the three unknowns

Linked rather than copied, per repo convention.

- [Jalle19/eda-modbus-bridge](https://github.com/Jalle19/eda-modbus-bridge) —
  HTTP/MQTT bridge for Enervent EDA and MD units, GPL-3, actively maintained.
  **Not a component to adopt here** — this project is ESPHome without MQTT —
  but its documentation is the prior art for the connection and the registers.
- [docs/CONNECTION.md](https://github.com/Jalle19/eda-modbus-bridge/blob/master/docs/CONNECTION.md)
  — the 4P4C pinout above, and the slave-address rule below.
- The Enervent *Modbus Registers* document is the register map, hard to find and
  linked from that project. Part of its `docs/` is marked proprietary, so it
  stays linked and out of this repo.

**The slave address has a trap of its own.** Read *Modbus address* from the
control panel — the manual gives the password — and **if it reads 0, change it
to 1.** Zero is broadcast in Modbus and is not a valid slave address, so a unit
left at 0 will never answer a read no matter how correct the wiring is.

Serial settings are not in that documentation. This file's 9600 8N1 is a
starting point and 19200 is the other candidate; it is a one-line change and
cheaper to try than to research.

### The board in stock

Three ESP32 boards are on the shelf: **two of this type** — photographed in
[`esp32-devkit.jpg`](esp32-devkit.jpg) — and one DevKitC WROOM-32U, which
belongs to [`../hirvirata/`](../hirvirata/). Take one of the pair; the other is
[`../axioma.effection/`](../axioma.effection/)'s. **All three are allocated**,
so a fourth board is a purchase.

What the photo settles:

- **30-pin DevKit layout**, 15 pins per side. Every pin in the wiring table below
  is brought out on it.
- **USB-C**, not micro-USB, and the USB bridge is a **CH340C** — so it is the
  CH34x driver that has to be present on the flashing machine, not CP210x.
- On-board **AMS1117-3.3** regulator, and a `VIN` pin, so 5 V may be fed in
  directly instead of over USB.
- The module carries a **printed PCB antenna**, so it needs no antenna part —
  right for this project, since a ventilation unit sits indoors where a PCB
  antenna is enough.

  **The shield reads `ESP-32`, not `ESP32-WROOM-32`.** This file used to call it
  a WROOM-32; that was inferred from the antenna and the footprint, not read off
  the part. Functionally it behaves as one and ESPHome's `esp32dev` profile
  fits, but a genuine Espressif WROOM prints its own name on the can. Treat the
  module as an unbranded equivalent — which matters only if a datasheet-level
  question ever comes up, and not for pin assignment or flashing.

## Found in the same box: a GYBMEP sensor breakout

Not part of the plan, and not needed for Modbus — recorded because it turned up
with this project's parts. [`gybmep-sensor.jpg`](gybmep-sensor.jpg).

Ordered as an **APKLVSR BME280 module, pack of two**, sold as the real BME280
with humidity, 5 V tolerant, I²C. **Both are here and both look identical**, so
the pair never got split across projects — which also means there is no second
box to point at what they were bought for. No project in this repo has ever
documented a use for them, and nothing in the git history does either. The
purpose is simply not recorded.

Two identical boards means one is spare whatever they end up doing.

The purple `GYBMEP` breakout is the common Bosch BME280 / BMP280 board: a 662K
(XC6206) 3.3 V regulator and level shifting on board, so it accepts 3–5 V, and
the four-hole version is **I²C only** with the address fixed on the board —
usually 0x76. Scan the bus rather than assume.

**Confirm which sensor actually arrived.** The listing says BME280, but these
purple boards are routinely shipped as BME280 while carrying a BMP280, which
measures temperature and pressure but **not humidity** — the one reading that
would make this module worth using here. Register 0xD0 settles it: 0x60 is a
BME280, 0x58 a BMP280. ESPHome reports it at startup — `bme280_i2c` refuses to
start against a BMP280, and `bmp280_i2c` is the component for that case.

If it turns out to be a real BME280 it is worth something here: supply and
extract air humidity is exactly the reading a ventilation unit's Modbus register
map may not expose, and it rides on the same ESP32 over I²C without touching the
RS-485 side. That is a later decision, not part of getting Modbus working.

## Why ESP32 instead of ESP8266 — a stock question, not a technical one

**An ESP8266 would do this job.** Modbus RTU at 9600 baud is a light load, and
the UART constraint that looks like a blocker has a clean fix. This file used to
list "multiple hardware UARTs" and "better ESPHome support" as reasons; that is
vague enough to read as *the ESP8266 cannot*, which is not true.

**The constraint, precisely.** The ESP8266 has one full hardware UART. UART0's
RX and TX are the pins the USB console and serial logging use, and **UART1 has TX
only** — its RX pin is committed to flash. Modbus needs both directions, so the
options are UART0 or a software serial port.

**And UART0 is the right answer, because the log does not depend on it.** Set
`logger: baud_rate: 0` and the serial console is released for the `uart`
component while **logging continues over the ESPHome API on WiFi.** That is
standard practice rather than a compromise, and it is why the old wording
"requires disabling the serial logger" overstated the cost.

What is genuinely given up:

- **The serial console**, and with it the two things that only ever appear
  there: setup-phase lines and a panic backtrace. That cost is invisible until
  something breaks in a way that prevents booting — see
  [`../axioma.effection/CLAUDE.md`](../axioma.effection/CLAUDE.md), where an API
  log stream could not show a radio driver's own register read.
- **RAM headroom**, if the register map turns into 50–100 entities. A listening
  configuration with a handful of sensors is nowhere near that.

**So the reason to use the ESP32 here is which board is scarcer.** One of the
DevKit pair is already allocated to this project and using it costs nothing;
the spare D1 mini is the documented fallback for
[`../stiebel.eltron/`](../stiebel.eltron/) — the only system in this repo that
is actually running — and it is shared with [`../hirvirata/`](../hirvirata/).
Spending the scarce part to save the plentiful one is the wrong way round.

**The migration path stays open, and it is three lines.** `esp32:` → `esp8266:`,
the UART pins to GPIO1/GPIO3, and `logger: baud_rate: 0`. Of the three projects
holding an ESP32, this is the one that moves most cleanly — worth knowing if a
board is ever needed elsewhere in a hurry.

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

## ESP32 ↔ RS-485 module wiring

Drawn out in [`wiring.svg`](wiring.svg), together with the unit side and the
checks that come before anything is plugged in.

**The module in stock switches direction by itself.** Five JZK TTL↔RS-485
boards were bought, described as having *automatic hardware flow control*: the
driver enable is handled on the board from activity on the TX line, and no
control pin is brought out to the MCU. That removes a wire, a GPIO and a line of
YAML.

| RS-485 module | ESP32 |
|---------------|-------|
| RXD | TX (GPIO17) |
| TXD | RX (GPIO16) |
| VCC | 3.3 V |
| GND | GND |

Note the crossover: the module's RXD takes what the ESP32 transmits.

With this board there is **no `flow_control_pin`** in the ESPHome `uart:` block.
Auto-direction boards derive their turnaround from the baud rate, so keep an eye
on it if the unit turns out to run faster than the usual 9600 or 19200 — at
Modbus RTU speeds it is a non-issue.

**Check the board before wiring.** If the one you pick up has `DE` and `RE` pins
brought out, it is the classic MAX485 breakout instead, and it needs the older
scheme: tie RE and DE together to a GPIO (GPIO4 works) and declare that GPIO as
`flow_control_pin`. Then the pin names are RO → RX and DI → TX rather than
TXD/RXD.

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

## Connector notes

The Enervent uses a modular connector rather than screw terminals, and it is
4P4C — see above for why that matters and what it rules out.

A breakout board is **not required** if:

- a 4P4C cable is used
- one end of the cable is cut
- the conductors are stripped and connected directly to the module

A breakout only makes identifying the pins easier, and an RJ11 one will not fit.

## Important Warning

Do **not** assume the pinout, even the one in this file.

The connector carries:

- RS-485 A/B
- Ground
- **A supply voltage** — pin 1, +5 VDC

Verify with a meter before wiring, and find that supply pin first so it can be
left alone.

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

All three now have a documented source, so what is left is verification on this
unit rather than research:

1. **Connector and pinout** — 4P4C with the pin table above, unverified for
   Pegasos and unmeasured on this cable
2. **Modbus slave address** — read it from the control panel, and change 0 to 1
3. **Enervent Modbus register map** — the *Modbus Registers* document, linked
   above

The blocking item is none of those: it is **having a 4P4C cable in hand.**

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

The first two cost nothing and decide what gets ordered:

1. **Count the positions in the jack** — four or six. Everything else waits on
   this, because it is the one step with a delivery time behind it.
2. **Read the Modbus address from the control panel**, and change it to 1 if it
   reads 0.
3. Get a 4P4C cable, cut one end, and identify the conductors by colour — then
   confirm with a meter which colour reaches which contact, because handset
   cords are reversed.
4. Wire red → A, green → B, yellow → ground, **black to nothing**.
5. Flash ESPHome with `uart` and `modbus_controller`, 9600 8N1, and one read
   request. If nothing answers, swap A and B, then try 19200.
6. Identify the registers against the Enervent document.
7. Add sensors, switches and controls, and integrate with Home Assistant.

## Long-Term Goal

Create a completely local integration for the Enervent Pegasos Eco ECE that provides monitoring and control through Home Assistant without relying on any cloud service.

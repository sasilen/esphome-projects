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
  this file said RJ11 until the connector was looked at.
  **Prefer a straight cable over a coiled handset cord.** Coiled cords are
  usually *tinsel* wire — copper foil wound around a textile core, chosen
  because it survives being coiled and uncoiled for years. It neither solders
  nor crimps reliably, and this project ends with stripped conductors in a
  screw terminal

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

### What is on the board

Three things worth knowing before wiring, none of them obvious from the pin
tables:

- **Every connection on this board is a solder pad.** No screw terminal and no
  header are fitted: four holes on the logic side, three on the bus side, and
  all seven have to be soldered. That is two soldering jobs, not one.
- **The bus side has three pads — `A+`, `B−` and a ground of its own** — and
  that ground is **not** the logic side's. The two are separate nets: the
  bus-side one belongs to the surge protection, the logic-side one is the
  signal common. It decides where the unit's ground conductor goes, and the
  answer is not the one the labels suggest — see step 7.
- **Two LEDs, Send and Rec.** They are the fastest diagnostic this project
  has: the send light proves the ESP32 is transmitting, the receive light
  proves something answered. Between them they split a silent bus into two
  halves without reading a single log line.
- **A fuse and dual TVS diodes are already fitted.** The separate bus
  protection that [`../stiebel.eltron/`](../stiebel.eltron/) has to buy is not
  needed here — this board carries it.
- **A 120 Ω terminator is on the board but out of circuit**, brought in by
  shorting the pad marked `R0`. **Leave it open.** The manufacturer recommends
  shorting it for long runs, and this run is a couple of metres at 9600 baud —
  two orders of magnitude away from where reflections begin to matter. It is
  also the cheapest thing to try if the bus ever works *unreliably*, which is
  a different symptom from the silence the procedure below is built around.
- **2.54 mm pitch on both sides**, so an ordinary pin header fits either one.

The manufacturer settles the earth question in the same breath: connecting the
earth pad is for long outdoor runs with lightning exposure, and **"indoor short
distance transmission cannot access the earth."** This installation is indoors
and a couple of metres. The pad stays empty.

> **Pin 1 is +5 V. Leave it unconnected.** Find the supply pin with a meter
> before wiring anything, and do not trust pin numbers through the cable —
> handset cords are reversed end to end. Reasoning in [`CLAUDE.md`](CLAUDE.md).

### Doing it, in order

Each step ends in a check. **If a check fails, stop there** — every one of them
is cheaper to settle in place than to separate later from a bus that is simply
silent.

**1. Count the positions in the jack.**

> Four means the tables above. **Six means stop:** the pinout is then from a
> different unit and nothing below applies.

**2. Read the Modbus address from the control panel**, password from the
manual. Write down what it says. If it reads 0, change it to 1.

**3. Cut one end off the cable** and strip the four conductors. The plug stays
on the other end and the cable stays in the unit, which is powered for this
step.

**4. Identify ground with a meter, at the cut end.** Take one conductor as
reference and measure the other three against it. The correct reference is the
one where exactly one conductor reads **+5 V** and **no reading is negative**.
A negative reading means the reference is the supply, not ground — switch and
measure again.

> Expect black +5 V, yellow ground, red and green data. **Those colours are the
> convention for 4P4C cordage, not a promise about this cable.** The meter
> decides, not the table.

**5. Mark the +5 V conductor and cut it back short.** A conductor that has been
identified and removed cannot slip into the wrong screw. It is the only way
this project can destroy anything.

Then unplug the cable from the unit.

**6. Wire the ESP32 to the module** — four wires, tables above, power off. Mind
the crossover.

> The module ships bare: **nothing is fitted to either side**, so both the
> four logic pads and the three bus pads have to be soldered. Hold a header
> square by pressing it into a breadboard, or tack one end pin and straighten
> by remelting that single joint before doing the rest. Check for bridges
> between adjacent pins before the board sees power.
>
> **Fit a header on the bus side too, not the cable directly.** The bring-up
> sweep includes swapping A and B, and with the conductors soldered in place
> that is two desolderings per attempt. Three pins and jumpers make it a
> five-second change. Solder the cable in permanently once the bus answers.

> Measure between 3V3 and GND before applying power. A short there is a
> misplaced jumper, and it is cheaper to find with a meter than with smoke.

**7. Wire the module to the cable** — red to `A+`, green to `B−`, black to
nothing.

**Yellow does not go to the ground pad next to `A+` and `B−`**, and that is the
counter-intuitive part of this board. The two sides carry separate grounds: the
bus-side one is the earth return for the surge protection, and the logic-side
one is the signal common. **Yellow joins the logic-side GND, on the same net as
the ESP32.** The bus-side ground pad stays empty — there is no protective earth
in this install to connect it to.

That is what "one net, one reference" in [`wiring.svg`](wiring.svg) means. An
RS-485 receiver measures a differential against its own common; if the unit's
ground is tied to a net the receiver does not share, there is nothing anchoring
the pair and the common-mode voltage is free to drift out of range.

The bus side has no signal ground of its own to use instead — `A+`, `B−` and
earth is the whole of it — which settles the question by elimination rather
than by preference.

**8. Flash and verify before the cable goes anywhere near the unit.** Power the
ESP32 from a separate USB supply — not from the unit's +5 V, which is a
different experiment for a later day. The cable is still unplugged.

Check the log for three things: the board boots and joins Wi-Fi, `modbus` and
`modbus_controller` start without error, and the probe begins trying. **A
timeout here is the correct result** — nothing is connected yet.

> This step is the whole reason for the order. It separates "the node is
> broken" from "the bus is silent", and those two produce the same symptom if
> they are tested together.

**9. Plug the cable in and watch — the LEDs first, then the log.** The two
lights answer a question the log cannot, because they sit on the wire rather
than in the software:

| Send | Rec | Means |
|---|---|---|
| blinks | blinks | both directions work; whatever is wrong is in the protocol, not the wiring |
| blinks | dark | **the ESP32 transmits and nothing answers** — slave id, baud, polarity, or the unit is not listening |
| dark | — | nothing is being sent. The fault is on the ESP32 side: UART pins, the crossover, or the config |

The third row is the one worth having. A dark send light means the four-way
sweep below would be wasted effort, because the problem is upstream of the
bus entirely.

Then the log, which says the same thing in more detail:

| Log | Means |
|---|---|
| `received: 01 03 02 ...` | the register exists and answered |
| `Modbus error ... 02` | **the unit is alive**, the register address is wrong |
| nothing at all | work through the four combinations below |

The first two both mean the bus works and only the register map is left. For
the third, sweep baud and polarity — four combinations, none of which can
damage anything:

|  | A→A, B→B | A↔B swapped |
|---|---|---|
| **19200** | 1 | 2 |
| **9600** | 3 | 4 |

## Modbus settings

Starting point, all to be verified against the unit:

| Setting | Value |
|---|---|
| Protocol | Modbus RTU |
| Baud rate | **19200** (9600 is the fallback — see below) |
| Frame | 8N1 |
| Slave ID | read it from the control panel — **and change 0 to 1** |

ESPHome components: `uart`, `modbus`, `modbus_controller`.

## The configuration

[`pegasos.enervent.yaml`](pegasos.enervent.yaml) is written and waiting. It
**reads nothing and proves one thing**: that the unit answers. The register map
is not in hand, so its single register address is a placeholder — and it does
not need to be right, because a slave that is alive answers an unknown register
with an exception, and an exception is a reply.

The two values to sweep are `substitutions:` at the top: the slave address and
the baud rate. Both are one-line edits followed by a re-flash.

Validate before flashing; it has not been through ESPHome's schema yet:

```sh
podman exec esphome esphome config /config/pegasos.enervent.yaml
```

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

1. Get the cable — the only item with a delivery time
2. Work through [Doing it, in order](#doing-it-in-order). It ends with the unit
   either answering or not, and both are informative
3. Identify the registers, then add sensors, switches and controls
4. Integrate with Home Assistant

Steps 1 and 2 of that procedure — counting the jack positions and reading the
Modbus address from the panel — **need no cable and can be done today.** They
remove two of the four things that cause silence, which is what turns a failed
first attempt from open-ended into a four-line table.

Full notes: [`CLAUDE.md`](CLAUDE.md).

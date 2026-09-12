# Enervent Pegasos Eco ECE → Home Assistant (ESPHome)

> **Technical details and reasoning.** Overview: [README.md](README.md).

## Goal

Read the ventilation unit's fault state into Home Assistant, and optionally
select its fan speed, **using the potential-free terminals the control board
already provides.** Locally, over the ESPHome native API, without MQTT.

## What the unit is

| | |
|---|---|
| Unit | Enervent Pegasos eco ECE |
| Automation | **ECC05** |
| Panel | ECC-05(E) membrane keypad — no display, LEDs for speeds 1–4 and setpoint |
| Fans | EC, driven 0–10 V from the control board |
| Afterheater | electric — the `E` in `ECE` |

The manual defines the suffix itself: *"EC = Ilmanvaihtolaite ECC05-ohjauksella,
ilman jälkilämmitystä. ECE = Ilmanvaihtolaite ECC05-ohjauksella ja sähköisellä
jälkilämmittimellä."* **The `E` means ECC05 plus electric heat**, so the model
name states the automation generation and there was never anything to infer.

---

# The Modbus route is closed

This project assumed Modbus RTU over a 4P4C "Freeway" service port for eighteen
commits. That assumption is wrong, and the manufacturer's own documentation
settles it three ways.

**The word "Modbus" does not appear in the ECC manual.** Forty-four pages,
covering every unit with ECC automation including `Enervent Pegasos eco EC(E)`,
zero occurrences. Nor "RS-485", nor "Freeway".

**Both 4P4C connectors are control-panel ports.** The external-cabling table
names them:

| Point | Description | Supplied |
|---|---|---|
| `OPpanel1` | Ohjainpaneeli | 1 standard, bus traffic, 20 m RJ 4P4C |
| `OPpanel2` | Ohjainpaneeli | **accessory, up to 2 more**, bus traffic, 20 m RJ 4P4C |

The parts list agrees: *"Ohjauspaneeli ECC-05(E), kojeeseen voidaan kytkeä
maks. 1+4 kpl paneelia."* Up to five panels on a private protocol. There is no
service port among them.

**The two-connector observation does not discriminate.** An EDA board also
carries two 4P4C jacks, both marked `RJ11 FREEWAY`. Counting connectors was
never going to settle which board this is; the panel did, and the model name
would have.

## The error, and its class

Every wrong fact in this file's history came from one source —
[Jalle19/eda-modbus-bridge](https://github.com/Jalle19/eda-modbus-bridge) and
its connection document — which says plainly that it supports **EDA and MD**
automation and names Pingvin, Pelican and Pandion. This unit is the generation
before.

**This repo already had a rule against exactly this.** From
[`../stiebel.eltron/CLAUDE.md`](../stiebel.eltron/CLAUDE.md), about a service
connector pinout taken from a different heat pump series:

> **WPC is a different series. Do not transfer these numbers.**

The rule was written down, and then the same transfer was made here anyway —
because the source was specific, confident and about the right manufacturer. A
pinout that matches the connector you are holding is not evidence that the
protocol behind it is the one the source describes.

## A confident summary is not a source

Two ready-made answers arrived during this investigation, both fluent, both
citing real documents, and both wrong in ways that a check caught in minutes:

- one claimed an *"official Freeway AC/ECC bus guide"* stating Modbus RTU at
  **19200/EVEN**, citing eda-modbus-bridge — whose code reads
  `parity: 'none'`, and which contains no such guide
- one claimed the board is a *"Picco or AC automation card"* and the panel bus
  is **I²C**, citing the ECC manual — which defines `ECE` as ECC05 and never
  mentions I²C, and which specifies a 20 m cable to up to five panels, a length
  I²C cannot drive

**Three of four register numbers in the first were correct**, which is what
makes this hard: the errors were mixed with accurate detail. The check that
caught both was the same one this repo applies to element lists and pinouts —
open the cited source and read the line.

---

# What the board actually offers

From the manual's connector list. `Ruuvi` = screw terminal, `Pika` = quick
connector.

| Terminal | Function | Notes |
|---|---|---|
| `S1` `S2` `S3` `S4` | **fan speeds 1–4** | potential-free contact |
| `OVERP` | overpressure / fireplace boost | momentary, spring-return button |
| `STOP` | ventilation emergency stop | potential-free |
| `ALARM` | external fault in (fire, frost) | potential-free |
| `LTOC` | cooling recovery | max 35 V |
| `NC` `COM` `NO` | **fault output** | potential-free, max 250 VAC / 1 A |
| `T1` `T2` `T3` | outdoor, post-HRC supply, supply sensors | `Pika`, the board's own inputs |
| `AFTHEAT` | electric afterheater control | ECE models |
| `TF CTRL` `PF CTRL` | **0–10 V to the fans** | see below — not an input |

**The manufacturer documents the pattern this project will copy.** The wiring
diagram shows an external humidity hygrostat wired to the `S1`–`S4` terminals to
change speed: *"nopeuksille (S1–S4) liittimet 2 (tehostusnopeus) ja 3
(normaalinopeus)"*. A relay doing the same thing is not a hack; it is the
documented way to control this unit from outside.

## `TF CTRL` and `PF CTRL` are outputs, and driving them is the one way to break something

The connector list reads `Pika TFCTRL` **0-10 V tulopuhaltimelle** and
`Pika PFCTRL` **0-10 V poistopuhaltimelle** — *to* the supply fan and *to* the
exhaust fan, listed alongside the `T1`/`T2`/`T3` sensors and `AFTHEAT` as the
board's connections to the unit's own components. They are the board's fan
drive.

The same names also appear as **trimmers**: *"Ohjainkortin trimmerit ilmamäärän
säätämistä varten"*, next to `FANSPEED CTRL` and `TFDIFF` with percentage bands
for each speed step. Neither reading is an external control input.

Two consequences:

- **Injecting a voltage there fights the board's own driver** — two sources on
  one node.
- **Cutting the board out and driving the fans directly discards the unit's
  logic**, and the manual shows how much of it is tied to fan speed: during
  defrost the supply fan stops and the exhaust fan runs at speed 3, on a
  two-hour check cycle below −15 °C. Frost protection and the afterheater go
  with it.

Stepless control would genuinely beat four steps. It is not available here at
an acceptable price.

---

# Keep for EDA readers: the official register map

This does **not** apply to this unit. It is recorded because it was expensive to
find and because it is authoritative — Enervent's own KNX adapter instructions,
which describe the gateway as an `IntesisBox KNX-Modbus RTU master` on the
Freeway port, making that port a Modbus slave on **EDA** boards.

Bus settings: `RS485`, baud `19200`, slave address `1`. Parity is not stated;
eda-modbus-bridge uses none.

Freeway pinout, from Enervent's own drawing — `20 m RJ4P4C erikoiskaapeli`, a
*special* cable:

```
PIN 1 - 5 VDC     PIN 2 - +     PIN 3 - -     PIN 4 - GND
```

Holding registers, value × 10 for temperatures:

| Register | Signal |
|---|---|
| `3x0006` | Outside air temperature |
| `3x0007` | Supply air temperature after HRC |
| `3x0008` | Supply air temperature |
| `3x0009` | Waste air temperature |
| `3x0010` | Exhaust air temperature |
| `3x0011` | Exhaust air before HRC (heat pump units) |
| `3x0013` | Exhaust air humidity, 0–100 % |
| `3x0029` `3x0030` | HRC efficiency, supply and exhaust side |
| `3x0046` | Room temperature average |
| `3/16x0053` | **Ventilation output, RW, 20–100** |
| `3/16x0135` | Temperature setpoint, RW, 10–40 °C |

Coils `1x0001`–`1x0012` carry away, away long, overpressure, cooker hood,
central vacuum, max heating, max cooling, manual forcing and summer night
cooling; `1x0041` and `1x0042` are alarm A and B, read-only.

**Note what `0053` is not.** Ventilation output is a **percentage, 20–100**, not
a speed 1–4. The 1–4 concept belongs to AC-fan units, which the same document
encodes separately as `8-15 = AC fan speed 1-8`. An `eco` unit has EC fans and
answers in percent.

---

# Remaining unknowns

The blocking item is no longer a purchase. It is a decision.

1. **Whether the project is worth building at all**, and at what scope. The
   honest case is in [README.md](README.md) — it is a fault notification, not an
   energy project.
2. **Terminal designations, confirmed on this board.** The table above is read
   from the manual's text, extracted heuristically from a PDF whose tables did
   not survive cleanly. Confirm against the wiring diagrams at the end of the
   manual before wiring.
3. **Whether the fault output is normally-closed or normally-open in service** —
   `NC`, `COM` and `NO` are all brought out, so either polarity is available,
   but which one means "healthy" wants checking rather than assuming. This repo
   has been caught by exactly that inversion once already, on the heat pump's
   EVU contact.

## Not worth investigating

**Decoding the panel bus.** It is technically tractable — there is continuous
traffic, and a button press provokes a deterministic change, which is a better
handle than the heat pump's bus ever offered. But the payoff is the contents of
a keypad: four speed LEDs, a setpoint step, a few status lights. Almost all of
it is already on the screw terminals as dry contacts, and the one thing it would
add — reading what somebody set at the wall panel — is cheaper to get by
watching the panel's own LEDs.

Recorded so the question is not reopened without a reason.

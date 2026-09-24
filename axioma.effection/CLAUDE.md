# Axioma Effectio (Qalcosonic W1) → Home Assistant (ESPHome + CC1101)

> **Technical detail and rationale.** Overview: [README.md](README.md).

## Goal

Read an **Axioma Effectio / Qalcosonic W1** water meter straight into Home
Assistant using:

- ESP32
- CC1101 868 MHz
- the ESPHome API

**No MQTT.**

---

# The meter

From the photograph:

| Property | Value |
|------------|------|
| Manufacturer | Axioma |
| Model | Effectio / Qalcosonic W1 |
| SW | 1.03 |
| CE | M24 1621 |
| Type | LT-1621-MI001-034 |
| SN | 12345678 — placeholder, the real one is on the nameplate |
| Year | 2024 |

Probable Meter ID:

```
12345678
```

Note: the Meter ID is confirmed later from a received Wireless M-Bus
telegram.

---

# Hardware used

## Already in stock

- ESP32 DevKit, 30 pins — [photo](../pegasos.enervent/esp32-devkit.jpg)
- CC1101 868 MHz — [photo](cc1101-module.jpg)
- 868 MHz SMA antenna
- ESP8266 (not needed for this project)

## Why ESP32 and not ESP8266

**The program does not fit on an ESP8266.** The built image is 1,069,167
bytes, and the D1 mini's application partition with OTA is about a megabyte.
That is not a borderline case, and it is measured rather than estimated —
the figures and their comparison with the repo's other projects are under
"Platform support".

The component does not support the ESP8266 anyway, but size would have
settled it even if it did.

**The board is an ordinary 30-pin DevKit**, with a PCB antenna, USB-C and a
CH340C bridge. Five pins are enough, and there are thirty.

**No external antenna is needed.** wM-Bus is radio: the meter transmits on
868 MHz and the CC1101 hears it from anywhere within range, so **you choose
where the receiver goes** and you choose somewhere Wi-Fi reaches. In aidon
the equivalent constraint is real, because that board is physically attached
to the meter's port — here it is not.

So the board gets **one antenna only: 868 MHz for the CC1101.** That removes
the confusion this file used to warn about, when the candidate board was a
module needing a u.FL antenna and there were two antennas.

**The CC1101 module has a 26 MHz crystal**, which is the expected value.

**Antenna connection: the pigtail came with the module.** The photographed
corner shows neither an SMA nor a u.FL connector, so the antenna attaches
through it. This is therefore in order and no adapter is needed.

If the pigtail ever goes missing, a quarter-wave wire at 868 MHz is about
8.2 cm and is good enough for experiments with no connector at all.

### 8.2 or 8.6 cm — both are right, under different assumptions

Sources give **8.6 cm** for a quarter wave and this file has said **8.2 cm**.
Neither is an error:

```
λ    = 299 792 458 / 868.95 MHz = 34.50 cm
λ/4  = 8.63 cm                              in free space
     × 0.95 velocity factor                 with insulated wire
     = 8.19 cm
```

**8.6 cm is the theoretical free-space length, 8.2 cm is shortened for
insulated wire.** If you cut bare wire, use 8.6 cm; if insulated, 8.2 cm is
closer. The difference is half a centimetre and decides nothing in reception
— but it explains why two sources give different numbers.

**And in reception, tuning matters less than in transmission.** A poor match
reduces sensitivity but breaks nothing — at the transmitting end reflected
power can destroy something. This node never transmits.

### Three numbers for the link budget

| | |
|---|---|
| RX sensitivity | about **−110 dBm** |
| RX current | ~14 mA |
| Data rate | 0.6–600 kbps — wM-Bus T1 is 100 kbps, comfortably inside |

−110 dBm is the figure to judge reception against if the meter is not
audible. For comparison, Wi-Fi reads −56 dBm on this board on the desk.

### The duty-cycle limit does not apply here

The EU 868 MHz band has a **1 % duty-cycle limit**, which is worth knowing —
but it constrains nothing here, because this node **never transmits.**
Listening is unlimited.

Nor is the meter's ~16-second interval caused by it: a telegram lasts
milliseconds, so its duty cycle is in the per-mille range. The interval is a
battery-life choice, not a regulatory constraint.

---

# Architecture

```
Axioma Water Meter
        │
        │ Wireless M-Bus (868.95 MHz T1)
        ▼
    CC1101 Radio
        │ SPI
        ▼
      ESP32
        │ ESPHome API
        ▼
 Home Assistant
```

No MQTT.

---

# ESP32 ↔ CC1101 wiring

Drawn out: [`wiring.svg`](wiring.svg).

| CC1101 | ESP32 | |
|---------|-------|---|
| VCC | 3.3V | |
| GND | GND | |
| SI (MOSI) | GPIO23 | |
| SO (MISO) | GPIO19 | |
| SCK | GPIO18 | |
| CSN | GPIO5 | strapping |
| GDO0 | GPIO4 | `irq_pin` |
| GDO2 | — | **not connected** |

## Note

The CC1101 runs on 3.3 V only.

Never use 5 V.

## On the DevKit the D number is the GPIO number

The board's silkscreen does not say `GPIO18` but `D18`, and **it is the same
pin.** The upper row reads, in full:

```
3V3  GND  D15  D2  D4  D16  D17  D5  D18  D19  D21  RX0  TX0  D22  D23
```

**This differs from the Wemos D1 mini**, and there is a trap in that because
this repo has two board types: on the D1 mini `D5` is **GPIO14** and the
numbers have no relationship to each other. On the ESP32 DevKit the `D`
prefix is merely a prefix. Anyone moving between the two boards makes this
mistake once.

| YAML | Board marking |
|---|---|
| `clk_pin: GPIO18` | `D18` |
| `mosi_pin: GPIO23` | `D23` |
| `miso_pin: GPIO19` | `D19` |
| `cs_pin: GPIO5` | `D5` |
| `irq_pin: GPIO4` | `D4` |

**All seven wires go to the same row.** 3V3 and GND are its first two, D23
the outermost — the lower row needs no attention at all, which makes both
soldering and enclosing easier.

## The module has no pin markings on either side

The board is a small square, silkscreened only `CC11010 868MHz Module`.
Eight holes on one edge, three on the opposite one, **and not one pin name.**
The order therefore has to be recognised, not read.

**Two independent sources give the same order**, and both describe this
board physically — same silkscreen, same 8 + 3 holes. The generic "CC1101
module pinout" table, which describes a 10-pin card in a different order,
**does not apply here** and was discarded for that reason.

The orientation is settled from landmarks, because the board can be held
four ways: **crystal up and the text vertical along the left edge.** Then
the eight holes are on the right edge and the order from top to bottom is:

| # | Pin | → ESP32 |
|---|---|---|
| 1 | CSN | GPIO5 |
| 2 | GDO0 | GPIO4 |
| 3 | GDO2 | **not connected** |
| 4 | MISO | GPIO19 |
| 5 | SCK | GPIO18 |
| 6 | MOSI | GPIO23 |
| 7 | GND | GND |
| 8 | VCC | 3V3 |

On the left edge, **GND — ANT — GND**; the middle one is the antenna, and
the order is symmetric, so getting it the wrong way round does not matter.

Drawn out: [`wiring.svg`](wiring.svg).

**The hole pitch is 2.0 mm, not 2.54 mm**, so Dupont jumpers do not fit.
Solder the wires directly — thin, 0.2 mm² stranded or AWG30, because thick
wire tears the small pad off. In a permanent installation a soldered joint
is better than a connector anyway, which is the same reasoning as for
stiebel's bus conductors.

### And this is why the table can be trusted here

**Only VCC and GND can destroy the chip.** The other six are 3.3 V logic, so
a wrong guess there means nothing works — not that something breaks. The
risk is in two pins, not eight.

Those two can be identified with a meter and no source at all: **between
them the resistance reading climbs slowly** as the bypass capacitors charge,
whereas the logic pins read open to almost everything. If the pair is found
at the end of the row the table promises, the whole orientation is proven
with one measurement.

The same method as in stiebel, where the TJA1050's pins were identified with
three independent continuity measurements before anything was connected.

### The SPI clock is 1 MHz, and it shows in the log

The boot log prints `data_rate: 1000000.0`. That is the SPI bus speed, not
the radio's bit rate. The CC1101 would take 10 MHz, but 1 MHz is what the
sources recommend for development and what the component picks by itself —
there is nothing to change here.

## Strapping pins, and why only one of them is a problem

The chip reads certain GPIOs **at the moment of reset** to decide its boot
mode. After that they are ordinary pins, so a strapping pin may be used —
provided nothing holds it at the wrong level right then. An ordinary ESP32's
strapping pins are **GPIO0, 2, 5, 12 and 15**, and this wiring touches two.

**GPIO5 is safe.** It wants HIGH at startup, and CS idles HIGH. The same
reasoning is recorded in [stiebel](../stiebel.eltron/CLAUDE.md) for the same
chip.

**GPIO2 is not, and that is why GDO2 stays unconnected.** It wants LOW or
floating, and GDO2 is an **output** of the CC1101 — if it drives the pin
high during reset, the board does not come up in normal mode. The schema
change removed GDO2 from use without anyone aiming for this, but **the wire
should still not be left in place**: this file's own troubleshooting lists a
GDO line on the wrong pin as a cause of boot loops.

---

# CC1101 pinout

On most modules the pins are:

```
GDO2
GDO0
CSN
SCK
MOSI
MISO
GND
VCC
```

Check your own module's silkscreen all the same.

---

# ESPHome test configuration

> **This is `version_4`'s schema and does not build with the current
> component.** It is left in place because it is the correct form of the
> other generation, not an error — see "The versions are two generations".
> The version that runs is
> [`axioma.effection.yaml`](axioma.effection.yaml).

```yaml
esphome:
  name: watermeter

esp32:
  board: esp32dev

logger:
  level: VERY_VERBOSE

api:

ota:

wifi:
  ssid: "WIFI"
  password: "PASSWORD"

external_components:
  - source: github://SzczepanLeon/esphome-components@main

wmbus:
  mosi_pin: GPIO23
  miso_pin: GPIO19
  clk_pin: GPIO18
  cs_pin: GPIO5
  gdo0_pin: GPIO4
  gdo2_pin: GPIO2
  frequency: 868.95
  log_all: true
```

---

# What should appear in the log

When the meter transmits a telegram, the logger shows something like:

```
Received T1 A frame from 12345678 RSSI -70
```

If this appears:

- the radio works
- the wiring is right
- the frequency is right
- the meter is audible to the receiver

---

# Open: why no frames arrive

**The radio works — that is proven.** Connected and a couple of metres from
the meter, the log produced:

```
[D][packet:106]: Have data from radio (8 bytes)
[D][wmbusmeters:351]: raw packet "320C800948884A28"
```

**SPI and GDO0 are in order here**, and the reasoning is stronger than the
mere appearance of the line: varying bytes cannot come from a dead bus,
because an unanswering MISO reads a steady zero or `0xFF`. The interrupt
fires and real data is read from the FIFO.

**That does not mean the receive path assembles frames.** In three minutes
one eight-byte packet arrived, and there is no telegram in it: `0x32` and
`0x0C` are not L and C fields at all but undecoded chip-level data, and
eight bytes is exactly the constant that a failed header decode produces —
the reasoning is under "The header analysis of those 47 packets was not
valid". This used to say that `0x0C` is an invalid C field; it was reading
the field from the wrong place.

**At two metres, reception does not explain the silence.** Our own meter's
telegram should arrive strong and complete. The antenna is attached to the
ANT pad, and it is a coiled copper wire, i.e. a helical antenna — a
radiator, not just a transmission line.

That leaves **three** questions rather than one, and they have to be kept
apart: does the meter transmit, does it transmit in a mode this component
understands, and does the component assemble a frame if a transmission
arrives. They are hypotheses 2, 1 and 3 below. **No measurement so far has
separated them**, because all three look the same in the log.

## There is experience of this in this repo

The whole aidon project started from the same thing:

> **The port is dead by default.** The network company has to activate both
> the interface and the 5 V supply. This is the project's one step that
> cannot be hurried — order it first.

The water meter has the same possibility, but in a different form: **this is
not a walk-by reading versus a fixed network.** The same device transmits
every 16 seconds inside a schedule window and is silent outside it, and the
default window is **Mon–Fri 06:00–18:00.** Which reading method is in use
therefore settles nothing — the time of day settles it.

This file's **`about a 16-second interval` comes from a general source and
was not measured from this particular meter.** It is an assumption in the
same way as the tables this project has had to overturn four times. The
importer's sales material gives the interval as **5 minutes**, which
contradicts the 16 seconds — neither has been verified from this meter, and
an NFC read would say.

**Ask that at the same time as the AES key.** All of them take calendar time
and all go to the same recipient:

1. **Is `wMBus T1` on at all — and can you switch it on?**
2. In which mode does it transmit — T1, C1 or S1?
3. The AES-128 key

Item 1 changed from "is radio transmission on" into this when it turned out
that **the meter is on LoRaWAN metering.** The question is then not whether
the radio is on but whether *this* radio is on, and the answer is probably
no — see "The answer is probably this". That makes item 1 a request to
change a setting in their own device, and **a refusal is an honest
possibility there** on battery grounds.

Item 2 is still on the list, because it is the only one that can invalidate
the hardware choice: T1 and C1 come with the same listening, S1 needs a
different receiver.

**Do not present the conclusion "the meter does not transmit"** — ask
neutrally. This file's own reasoning about it has had to be retracted twice,
and there is still an open suspect on the receiver side — see hypothesis 3.

The request includes **the real serial number from the nameplate.** In the
repo it is the placeholder `12345678`, because the repo is public.

## The overnight run did not settle it: it fell outside the window

8.5 hours a couple of metres from the meter, on 868.95 MHz:

| | |
|---|---|
| Complete frames | **0** |
| Raw packets | 47 |

**Zero is an expected result here, not an observation.** The Qalcosonic W1's
default schedule is **Mon–Fri 06:00–18:00**, and outside it the radio is
silent altogether — the battery is specified for 15 years. The run started
on Sunday at about 21:15 and ended on Monday at 05:45, so it was entirely
outside the window and doubly so at a weekend.

The schedule is masked at both weekday and month level. The source is not
the manufacturer's datasheet but an independent builder who hit exactly this
symptom, and wmbusmeters' maintainer confirms the phenomenon is common: some
meters switch the radio off at night and at weekends in their default
configuration. The masks are readable from the meter over NFC, so the
assumption can be checked from the device — see "The meter's own
configuration is readable over NFC".

**The comparison figure still holds when the measurement is made inside the
window.** At two metres, a meter transmitting every 16 seconds would produce
about 1900 receptions in 8.5 hours.

### The header analysis of those 47 packets was not valid

This used to say that four properties together showed all 47 to be noise.
The conclusion is probably right, but **two of the four arguments do not
measure what they claim.**

`packet.cpp` attempts T1's 3-of-6 decoding on the first three bytes. If even
one six-bit code is invalid, the decode returns empty and the L field falls
back to 0 — from which `expected_size` computes `(3·5+1)/2 =` **8**. With
random data the decode passes with about 0.4 % probability, so in practice
every noise hit produces the same number.

Two consequences:

- **Eight bytes is not a read granularity but a computed constant.** It is
  the component's signature for "I could not open the header" and says
  nothing about the signal either way.
- **The bytes printed in the log are not L and C fields.** `convert_to_frame`
  attempts the decode only later and fails the same way, so the output
  contains undecoded chip-level data. The claim "not one C field is valid"
  is reading a field that is not in that position. This can be checked
  against the log's own example: `0x32 = 0b00110010`, and `>>2 = 0b001100`
  is not in the 3-of-6 lookup table, so the decode fails on the very first
  segment.

Two valid arguments remain: the packets differ in content and have no
rhythm. They are enough to say that no source repeats, but **they do not
separate noise from our own meter's frame whose header decode failed.**

This is the same lesson for the third time in this file: **a table is a
hypothesis, the device's own utterance is evidence** — and this time the
wrong table was our own.

### Hypothesis 1: wrong frequency — not testable with this component

There are two wM-Bus modes on the 868 band, and we listen to only one:

| Mode | Frequency |
|---|---|
| **S** | **868.30 MHz** |
| T, C | 868.95 MHz |

**This used to say the hypothesis was tested and disproved on 7.9.2026. That
is retracted: the test was incapable of detecting what it claimed to rule
out.**

`transceiver_cc1101.cpp` writes the whole register table with fixed
literals, and **only** FREQ2/FREQ1/FREQ0 are derived from the `frequency`
setting:

| Setting | Register | |
|---|---|---|
| 100 kbps | MDMCFG4 `0x5C`, MDMCFG3 `0x04` | fixed |
| 2-FSK, Manchester **off**, 16/16 sync | MDMCFG2 `0x06` | fixed |
| Deviation ~50 kHz | DEVIATN `0x44` | fixed |
| Sync word `0x543D` | SYNC1/SYNC0 | fixed |

The code's own comment says it outright: `Configure for wM-Bus Mode C/T at
868.95 MHz, 100 kbps, 2-FSK`.

**So `frequency: 868.30MHz` moved only the local oscillator.** S mode is
32.768 kbps **Manchester-coded** with a different sync pattern; the receiver
was 100 kbps 2-FSK with no Manchester. It does not demodulate an S
transmission at any signal strength.

For the same reason the explanation tried here — "S mode is a noisier
channel, because its different modulation and rate settings trigger false
sync more easily" — cannot be right either: **not one modulation or rate
setting changed.** And a 43-minute run at 868.30 later produced **zero** raw
packets, which is the opposite observation to the six-minute sample the
noisiness claim rested on.

**The component does not support S mode at all.** The radio layer sets the
link mode only to C1 or T1, and `wmbus_meter`'s `mode:` options are `Any`,
`C1` and `T1`. This hypothesis therefore cannot be tested with this
hardware: if the meter is in S1 mode, the receiver has to change, and
rtl-sdr + rtl_wmbus handles S, T and C. **That is why the mode belongs on
the list of questions for the water utility** — it decides whether the whole
hardware choice is right.

**The other half of the reasoning holds: C1 was covered.** C1 and T1 share
the same radio settings, and C1 is recognised automatically from the
preamble byte `0x54` with no YAML setting. So the 8.5-hour run at 868.95
listened to both.

There is a trap in the commented-out meter block because of this: **`mode:
[T1]` would filter out C1 telegrams.** Leave the default `Any`.

### The answer is probably this: the meter is on LoRaWAN metering

**This meter is in LoRaWAN use.** That is known from the installation rather
than from the bus, and it explains everything measured above.

In the W1 the radios are **separate flags** — `LoRa WAN`, `wMBus T1`,
`wMBus S1` — not mutually exclusive but not coupled to each other either. If
the utility reads the meter over LoRaWAN, **it has no reason to keep the
wM-Bus radio on**, and one good reason to keep it off: the battery is
specified for fifteen years and every extra transmission comes out of it.
That is a configuration that would produce exactly this file's measurements
— a working receiver, the right frequency, the right mode, nothing to hear.

**LoRaWAN is not an alternative local route.** Transmissions go to the
utility's network server, and the payload is encrypted with session keys
that server manages. A local LoRa receiver — the component supports the
SX1276 and SX1262, so the hardware would exist — would see that
transmissions occur, but not their contents. **The keys are further away
than the AES key this started out asking for**, because they are not a
property of the meter but of the network.

Two consequences:

- **The first item on the question list changes.** No longer "in which mode
  does it transmit" but **"is wM-Bus T1 on at all, and can you switch it
  on".** That is a request to change a setting in their own device, and it
  may get a refusal on battery grounds — which is an honest reason rather
  than mere bureaucracy.
- **NFC becomes primary.** It is local, needs no key, no radio and no
  transmission window, **and it is unaffected by which radio the utility
  uses.** The meter's data is in the NFC interface regardless of whether it
  transmits anything.

**One hypothesis this raised, and which longer data overturns.** Those noise
packets could be the meter's own LoRaWAN transmissions, seen as rubbish by a
2-FSK receiver — LoRa is chirp spread spectrum and the CC1101 does not
demodulate it, but a chirp can trigger a false sync hit. A LoRaWAN water
meter transmits at regular intervals, so the hypothesis is testable from the
intervals.

Twenty packets' intervals over 30 hours are 30, 140, 66, 88, 72, 45, 128,
92, 25, 38, 15, 103, 130, 32, 50, 9, 210, 480 and 60 minutes. The range is
**from nine minutes to eight hours.** The counter-argument was that if the
receiver caught only a random subset of transmissions, the intervals would
still be multiples of a common base period — and they are not: no period
within an hour fits them even loosely, and even the best candidate's worst
deviation is **more than a third of the period.**

It is noise. **The entry is settled**, and what remains is what the 8-byte
bursts have been from the start: false sync hits.

### Hypothesis 2: the meter does not transmit while we listen

Three forms, cheapest first:

1. **The transmission window.** The default Mon–Fri 06:00–18:00 explains the
   overnight run as it stands. Check: listen on a weekday during the day.
2. **Transport mode.** In a new meter the radio is off and activates
   automatically once accumulated volume exceeds **10 litres**. The same
   event locks the configuration parameters permanently. Check: total volume
   is not zero.
3. **The radio is configured off.** This one goes to the water utility.

This is the same shape as aidon's obstacle, and its solution is the same:
ask, and ask early.

### Hypothesis 3: the receiver does not assemble a frame

This was not on the list at all, and it is worth keeping in mind before
drawing conclusions about the meter.

[Issue #425](https://github.com/SzczepanLeon/esphome-components/issues/425),
opened 2.8.2026 and still open: `wmbus_radio/CC1101 receives only noise
(8-byte packets, RX FIFO overflow) — never captures full telegrams`. The
pinned commit is the tip of `main`, so no fix exists and moving a pin does
not help.

The suspicion is that GDO0 fires on the FIFO threshold rather than on a sync
word hit. The RF settings are byte-for-byte identical between the
generations; the difference is in the read strategy:

| | `version_4` | `main` 5.1.7 |
|---|---|---|
| FIFO threshold at RX start | **4 bytes** | **32 bytes** |
| GDO2 as a sync gate | yes, its own state | not used |
| PKTLEN once length is known | switched to fixed mode | stays in infinite mode |
| `sync_mode` setting | present | absent |

**The symptom profile still does not match this device**, and that
distinction is worth keeping:

| | #425 | this device |
|---|---|---|
| Reporters | 1 | |
| Noise packets | every 1–3 s | 1 / 11 min |
| `RX FIFO overflow` | continuously | **none at all** |
| CPU starvation | yes | not observed |

The same 8-byte signature, a different intensity. It is a serious suspect
rather than an established cause.

### A full transmission window measured: zero frames

7.9.2026, Monday, 868.95 MHz, the meter a couple of metres away. **The first
measurement in this project that can be recorded as it stands** — three
earlier ones were overturned, because they measured something other than
what they claimed.

| | |
|---|---|
| Listened inside the window | about **7.5 h** (10:13 → 18:00, two flashes in between) |
| Noise packets | **6** — 10:11, 11:18, 12:46, 13:58, 14:42, 16:50 |
| Complete frames | **0** |
| `RX timeout` / `RX FIFO overflow` | **0** |
| FIFO threshold 32 vs. 4 bytes | no difference |

Expected value if the meter transmitted every 16 seconds: **about 1700
receptions.** Together with the overnight run, about 16 hours and zero
frames.

Four variables were right at the same time this time — the right frequency,
a mode the component supports, inside the transmission window, and a
receiver demonstrably alive. **The receiving side is therefore proven as far
as it can be without a frame**, and that is the reason to treat the meter's
side as primary.

One bookkeeping note: the `LOCAL PATCH` line is not in the capture log but
in the boot output of the flash. The configuration dump repeats only for a
**new** log client attaching, and the stream running in the background with
`>>` redirection was already closed — the same mechanism recorded in the
root CLAUDE.md.

#### And 20 hours afterwards unattended: the same zero

The capture was left on after the window ended and broke only at 14:00 on
8.9.2026, at a power cut. It gave for free what the window measurement does
not cover: the evening, the night and the next weekday morning up to midday.

| | |
|---|---|
| Extra time after the window | about **20 h** (7.9. 18:00 → 8.9. 14:00) |
| New noise packets | **12** — 20 in the whole log |
| Complete frames | **0** |
| Reboots | **0** |

Cumulatively that is about **36 hours of listening and zero frames.**

The run is at the same time the strongest evidence of receiver stability
there is here: `Uptime` ran uninterrupted to **95,584 seconds, i.e. 26.5
hours** from the last flash on 7.9. at 11:28. The board therefore did not
crash, hang or drop off the network once during the time it heard nothing —
and `Uptime` is the only line that distinguishes these, as recorded in the
root CLAUDE.md.

**This was not a planned measurement but a log left running.** It overturns
nothing new — the window measurement had already disposed of the
transmission-window hypothesis — but it removes the last doubt about timing:
inside and outside the window have now been measured back to back without a
break, and there is no difference on either side.

### Test: FIFO threshold 32 → 4 bytes

Done in a local working copy, because one byte cannot be changed in a remote
source. The tree is checked out from the same commit as the YAML's pin, and
**the difference is this one line** in `wmbus_radio/transceiver_cc1101.cpp`:

```c
// this->write_register(CC1101_FIFOTHR, 0x07);   // upstream: RX FIFO >= 32 bytes
   this->write_register(CC1101_FIFOTHR, 0x00);   // version_4: RX FIFO >= 4 bytes
```

`upstream/` is in .gitignore and third-party code does not enter this repo,
so **the change is recorded here so that it is reproducible without that
tree.** In the YAML, `external_components` points at a local path for now
and the GitHub source is commented out below it.

**The control is a second local addition, not the packet rate.** The line
`configuring FIFO threshold` is at VV level and therefore in setup, which
the API log stream does not see, and a tag's level cannot be raised above
the global one — the higher levels are compiled out. So a line was added to
`transceiver.cpp`'s `dump_config`:

```
[C][wmbus.transceiver]:   LOCAL PATCH: FIFOTHR=0x00 (RX FIFO >= 4 bytes)
```

`ESP_LOGCONFIG` is at C level and **the configuration dump repeats for every
log client attaching**, so the patched tree can be confirmed in the binary at
any time without a serial port. If the line is missing, the build did not
use this tree.

**And it earned itself immediately.** The first build with the local tree
produced a configuration dump without this line: `podman cp` had nested the
tree into `/config/upstream/upstream`, because the target directory already
existed, and the build read the old copy. Without the marker line it would
have looked like a successful test. **Copy the contents, not the directory:**
`podman cp <path>/upstream/. esphome:/config/upstream/`.

**The packet rate is not a valid control, and that was wrong here at first.**
`MDMCFG2 = 0x06` requires a 16/16-bit sync hit before the FIFO starts
filling, so the rate of noise packets comes from the probability of false
sync hits. The FIFO threshold only decides whether the burst after a hit is
delivered if it does not grow to 32 bytes. The effect is therefore moderate
rather than dramatic, and the measured difference — one packet in 65 minutes
versus about one in two hours — fits either conclusion equally well.

| Observation | Interpretation |
|---|---|
| `LOCAL PATCH` line in the log | The patch is in the binary. Only after this does silence mean anything |
| The line is missing | The build did not use the local tree — `esphome clean` and again |
| A complete frame | Hypothesis 3 is confirmed and the obstacle was in the receiver |

The third row is what the test is looking for. The first two are the
control, and it is needed here: **twice already a measurement has been
interpreted that did not measure what was assumed** — S mode with the wrong
registers, and 8-byte headers that were not headers.

If it is still silent after that, `version_4` is a demonstrably working
CC1101 implementation, but with two conditions: **GDO2 has to be connected
back** as a sync gate and **not to GPIO2** (strapping, argued above), and
#425's reporter says `version_4` crashes with current ESPHome versions. That
is why it comes last.

# AES-128 encryption

The Axioma Qalcosonic W1 normally uses AES-128 encryption.

The AES key is NOT found:

- on the display
- on the nameplate
- in the serial number

It is normally obtained from:

- the water utility
- the building manager
- the developer
- the meter's supplier

Without the AES key, normally only encrypted telegrams are visible.

# The meter's own configuration is readable over NFC

The W1 has an NFC interface, and **reading the configuration requires no
password** — only writing does. A phone therefore gets straight from the
meter the things this file has guessed at from general sources:

- radio state on or off
- `wMBus T1` and `wMBus S1` as separate flags — i.e. the **mode**
- the transmission window's weekday and month masks
- total volume, i.e. whether transport mode has already been released

This would be the cheapest way to check the transmission-window assumption,
and it is **the same rule as elsewhere in this file: the device's own
utterance beats the table.**

**In practice the route is closed**, and that is down to the apps rather
than the meter:

| App | |
|---|---|
| `Qalcosonic configurator W1`, `QW1 Radio Activator` | read without a password and showed the schedule masks — **removed from the Play Store**, only on APK mirrors now |
| **Axilink** | Axioma's current one, NFC and optical head — **password-protected**, credentials come from the reseller |
| **Axilink Lite** | free and official, would say whether the meter is active and transmitting — **cannot be installed on a Pixel 9** |

The password-free read this used to rely on **applied to the removed app**,
not the current one. The route therefore exists but is not free: it requires
either a reseller's credentials, an APK from a third-party mirror, or help
from the importer (Effectio Oy).

### And the phone does not see the meter — that is the phone, not the meter

A tap produced **nothing**: the phone did not detect a tag at all. That is
not an observation about the meter, and two reasons explain it from the
phone's side.

**The meter's NFC is ISO 15693, i.e. NFC-V**, not the NFC-A that phones use
for payments and stickers. This is inferred reliably but indirectly:
`esphome_qalcosonicnfc` reads the W1 with a **PN5180 chip**, which is
specifically an ISO 15693 reader.

**On Android, NFC-V is restricted.** The operating system offers only raw
`transceive` traffic with no NDEF support, and **Android 15 added a tag
permission system in which ISO 15693 is "restricted" unless an app is
explicitly on the allow list**; Android 16 added a confirmation dialog to
it. Without an NFC-V-capable app the system routes the tag nowhere, so **a
bare phone is silent even with the tag in the field.** That probably also
explains why Axilink Lite would not install on that phone.

The second reason is alignment. The meter's coil is in a precise place —
located
from the FCC filing — and a **3D-printed case exists that aligns the
PN5180's antenna** to it. If alignment needs a printed case, it is not
forgiving towards a phone's coil.

**The rule from this: a phone's silence does not belong on the meter's fault
list.** It is the same error shape as the S-mode test with the wrong
registers — a measurement that does not measure what its title says.

### That is why the PN5180 is no longer a fallback

[esphome_qalcosonicnfc](https://github.com/dbmaxpayne/esphome_qalcosonicnfc)
is a five-euro module, and it **defeats three obstacles at once**: no AES
key, no transmission window, and no dependence on which radio the utility
uses. There is a ready case model for antenna alignment.

The price has to be stated honestly, and it overturns one of this file's own
arguments: **the receiver has to go next to the meter.** It has been argued
here that wM-Bus is radio and therefore you choose the location where Wi-Fi
reaches — with NFC that freedom disappears, and the meter pit or the utility
room is then where Wi-Fi has to reach.

It is a different project rather than a fix to this one. But now that
thirty-six hours of listening have been spent here with zero frames, it is
**a more direct route than a radio with no evidence that it transmits.**

#### When buying a reader: the chip's name is the only thing that decides

**The reader has to support ISO 15693, and `PN5180` is in practice the only
cheap chip that does.** The others capable of it — RC663, ST25R3911B,
TRF7970A, CR95HF — are not off-the-shelf items.

**The RC522 will not do.** The MFRC522 supports only ISO 14443A, i.e. MIFARE
cards. Same 13.56 MHz, same SPI, same 3.3 V and often the same sales
description — **and it is a different protocol.** The same shape as the
lesson recorded in stiebel about an RS-485 module not doing for a CAN bus:
shared physics is not compatibility.

**The decisive signs are in the pin header, not in the shape of the board:**

- **`5V` and `BUSY` on the header.** The RC522 is 3.3 V only and has no
  ready line; the PN5180 works without neither. This is the fastest and
  surest check, and it can be done from a product photo if the silkscreen is
  visible.
- **The number of pins.** The MFRC522 brings out eight. The PN5180 needs at
  least nine and boards break out 10–16.
- **The chip marking**, `PN5180` or `PN5180A0HN`. If a listing says only
  "13.56 MHz SPI, compatible with Arduino" without the chip's name, it is an
  RC522.
- A price of €2–3 each in a lot of 3–5 is RC522 pricing; the PN5180 is €8–10
  each.

### The antenna's shape is not a valid identifier, and this said it was

There was a fourth sign here: *"the antenna is a small square on the same
board — the PN5180 is two-part"*. **That is wrong and it would have rejected
the right board.**

The module that arrived is single-board, **`PN5180-NFC` rev `R1.1-170710`,
70 × 39 mm**: one blue board with a coil antenna at the right end and at the
left a `PN5180A0` chip, passives and a thirteen-pin header `JP1`. The header
has both `+5V` and `BUSY`, i.e. both of the ones the RC522 lacks.

Being two-part is therefore **a property of one best-selling model, not a
property of the chip**, and it had been generalised into an identifier here
on the strength of a single product photo.

It is the same mistake this list's own opening warns against — shared
physics is not compatibility — only the other way round: **shared appearance
is not incompatibility.** The identifier is the chip's name and the
electrical requirement, not the shape.

So search by the chip's name `PN5180`, not by description. And check the
header for **both 5 V and 3.3 V** — the transmitter side needs five volts,
the logic three.

**Changing settings is not possible**, and the reason is structural: writing
parameters locks permanently once the meter has passed the 10-litre
threshold. The schedule of an installed meter is therefore not adjusted with
consumer tools — that is the utility's or the manufacturer's right.

**The meter has a communication credit**: use of the auxiliary interfaces is
limited to about 20 minutes per month to save the battery, and when the
limit is reached the interface locks until the hour turns. So do not poll
NFC hard.

The display is weaker evidence than this. The LCD has a radio communication
indicator, but **it has not been confirmed whether it means "radio
configured on" or "transmission in progress"**, and individual display pages
can be hidden at installation — the absence of a page therefore proves
nothing.

## The polling interval is derived from the credit, not from habit

The PN5180 has arrived, and the intention is to poll. That is fine — but the
interval has to be computed from the meter's communication credit rather
than chosen by what feels normal.

```
20 min/month  =  1200 s/month  =  40 s/day
```

**Everything depends on the duration of one read, and that is not known.**
Assuming two seconds:

| Interval | Reads/day | Consumption | |
|---|---|---|---|
| 1 h | 24 | 24 min/month | **over budget** |
| 2 h | 12 | 12 min/month | fits |
| 3 h | 8 | 8 min/month | roomy |

With a five-second read the same table shifts entirely: two hours is already
30 min/month. **Measure the duration of one read and derive the interval
from it with a factor of 2–3.** That is one measurement and it removes all
the guessing.

**Start at three hours.** Water is cumulative and Home Assistant's long-term
statistics are computed hourly, so a three-hour interval loses them nothing.
The only thing wanting more is leak detection, and a running toilet is
caught within the same day on eight readings. A roomy interval leaves
two-thirds of the budget in reserve for the duration estimate being wrong.

### The failure mode is silence, so the budget is made visible

When the limit is reached the interface **locks until the hour turns**. It
returns no error that would show in an entity — the read simply fails and
the old value stays put, looking fresh.

That is the same class of fault this repo has fixed five times in a single
week: **a watcher's silence and a watcher's blindness look the same.** So
this belongs built in from the start rather than added afterwards:

- **count the reads** and publish an estimate of consumed credit as an
  entity of its own
- **detect a failed read** and back off rather than retrying immediately —
  a retry spends the same budget that just ran out
- **let the entity go unknown** if a read has not succeeded for three
  intervals, so that an old reading does not pretend to be fresh

### A straight header stacks the boards; it does not stand the C3 up

This briefly said that a C3 soldered straight into `JP1` **stands
perpendicular** and sticks out a couple of centimetres from the surface, and
that getting it horizontal would need the pins bent. **That is backwards.**

A straight pin header passes through both boards' holes and holds them
**parallel** — that is how every add-on card attaches. A right-angle header
is the one that turns the joint into the plane of the board and puts the
second board beside the first.

The correct assembly is therefore a stack:

```
C3            1.2 mm
header        height selectable
PN5180        1.6 mm
------------  meter
```

About eleven millimetres with a standard header, and **the C3 covers the
left third**, i.e. where the circuitry is anyway. The antenna area stays
entirely clear: the C3's inner edge reaches ~21 mm and the coil starts at
~30 mm.

**The header's height is a design parameter, not a leftover.** The C3's
ground plane floats above the antenna's matching network `L1`/`L2`, and the
lower the header, the closer. A standard header leaves about six
millimetres of air — do not press the C3 down onto the surface even if it
would fit.

### Its own node on a C3; the radio node is left alone

**The NFC side is built on a separate ESP32-C3 SuperMini** rather than on
top of the existing `esp32dev` node. The reason is sequence, not hardware:
the radio's state is still an open question, and **an NFC read is what
answers it.** If the radio node is dismantled before the read, the question
closes permanently; if it is left alone, both are up when the answer comes.
The DevKit is dismantled only afterwards — or not at all, if the radio turns
out to be switched on.

Swapping the board is also cheaper now than after soldering, and there are
six C3s on the shelf.

**The antenna argument was checked and it fell.** This briefly said that
Wi-Fi at the meter is the worst in the house, because NFC forces the
receiver next to the meter. The owner corrected it: the meter is in the same
room as the 1-Wire node. Measurement confirms it is sufficient:

| Node | Wi-Fi |
|---|---|
| onewire, same room | **−70 dBm** (varying −69…−76) |
| stiebel | −77 dBm |
| axioma on the desk | −56 dBm |

−70 is not the best in the house, but it is **demonstrably sufficient**, and
the evidence is stronger than the reading: there is already a C3 in that
room, it has taken several OTA updates and streamed logs for days without a
break. Same board type, same room.

**That is why hirvirata's WROOM-32U stays with hirvirata.** Its external
antenna argument rests on a sparking brushed motor in a closed box, and this
project does not need it.

### First boot: association succeeded only on the sixth round

The node came up on the desk and read **−58 dB**, matching the radio node's
−56 dBm from the same place. But association took about two minutes, and the
failures are of two different kinds:

| Access point | Signal | Error |
|---|---|---|
| the farther one | −80…−81 dB | `Probe Request Unsuccessful` |
| **the nearer one** | **−60…−61 dB** | `4-Way Handshake Timeout`, `Authentication Failed`, `Handshake Failed` |

**The upper row is explained by signal strength, the lower one is not.** The
handshake failed three times against an access point whose field is −60 dB,
and eventually succeeded against the same access point with the same key —
so the password is right and the signal is sufficient. The network has two
access points on the same SSID **on the same channel 6**, which is either a
mesh backhaul or two access points interfering with each other.

**This has not been fixed or explained, only recorded.** It prevents
nothing: the board is on the network, `Boot seems successful` and the boot
loop counter reset. Its significance is that **the expected value at the
installation site is −70 dBm** — ten decibels weaker than the field where
the handshake already struggled. If association fails at the meter, this log
is what it is compared against, and the conclusion must not then be "the
C3's antenna is poor" until these three lines have been ruled out.

**The fallback AP has never been visible, on any board, anywhere — do not
use it as a diagnostic.** It was suggested three times in this project and
produced nothing each time, including on the desk where the node associates
in one round and Wi-Fi demonstrably works.

The reason is that the station and the AP share one radio: while the
association retry loop runs and `Restarting adapter` repeats, the AP's
beacons go out sporadically and a phone's scan never catches them. The log
said `Starting fallback AP` once and it still was not visible.

That also retracts an inference drawn from it: the AP's invisibility was
read as evidence that transmission does not get out. **The node associates
on the desk, so transmission works** — the AP is simply not observable here.

**The usable criterion is whether the device joins the network**, checked
from the server, not from a phone.

**And the fallback AP is not a valid sign for this phase either.** The log repeats
`Restarting adapter` on every round, and that takes the AP down and back up
— so `Axioma NFC fallback` flickers rather than staying in the network list.
A missing AP was first read here as proof that the board does not start at
all, and that was wrong: the board was up the whole time and trying. **The
serial port is the only honest way to watch the association phase**, because
the API log stream attaches only once the device is already on the network
and cannot, by definition, show why it is not.

### It was not a join failure but a drop, and the DHCP log separated them

The serial port showed an endless association attempt for hours:
`Authentication Failed`, `Handshake Failed`, `Auth Expired`,
`Association Expired`, `Restarting adapter`, a new scan. Four different
causes were inferred from it in turn — rejection by the network, a stale PMK
cache in NVS, an antenna damped by the PN5180's board, and a supply dip.
**All four were wrong.**

The answer came from the access point: **the MikroTik's log showed a DHCP
request and an address granted.** DHCP happens only after association,
authentication and the four-way handshake — so **everything being fixed was
already working.** The device associated, got an address and dropped out
shortly afterwards.

`Auth Expired` and `Association Expired` are not rejections but
**expirations**: the access point drops a client it believes has vanished.
MikroTik sends keepalive frames and its `disconnect-timeout` is short, and
**the ESP32-C3's power-save default is `LIGHT`**, which puts the receiver to
sleep between beacons. A sleeping radio misses the acknowledgements.

The fix is `power_save_mode: NONE`, and this is **the repo's first device to
earn it.** The root CLAUDE.md says it is not set without a symptom that
justifies it; this is that symptom.

**The lesson is in the choice of source, not in the radio.** ESPHome's log
records only the device's own side, and in it a drop looks identical to a
join that never succeeds. They are separated only by **the other party**,
and that party is nowhere in the device's log. The same shape as elsewhere
in this file: the device's own utterance beats the table — but when the
event is between two devices, **one device's utterance is not enough.**

A side note worth keeping: RSSI swung between −58 and −78 within the same
session in the same physical place, and it was inferred from that that the
PN5180's board damps the C3's antenna. **That was measuring a device in
flight**, associating and dropping continuously — scan readings are not
comparable when the radio restarts between them.

### First run: SPI comes up, the PN5180 does not answer

```
[C][spi:074]:   Using HW SPI: SPI2_HOST        CLK GPIO4 · SDI GPIO3 · SDO GPIO7
[D][PN5180:435]: Sending SPI frame: 04 02
[E][PN5180:444]: Step 3 - Failed to wait for BUSY_ pin to get high
[E][component:204]: qalcosonicnfc was marked as failed
```

Three things from this.

**The bus comes up per the diagram.** The pins are right in the
configuration and ESPHome brings the hardware bus into use. That part is
proven.

**The component does not hang.** It marks itself failed and stops; setup
continues and ends with `setup() finished successfully!`. **This overturns
the suspicion presented earlier in this file** that the `BUSY` wait would
eat the run time and take the device off the network. The driver has a
timeout on every wait, and the component does not retry.

**`BUSY` always reads low.** Step 0 waits for it to fall and passes; Step 3
waits for it to rise and fails. Three explanations, all measurable with the
board powered:

| | |
|---|---|
| `RST` reads 0 V | The chip is held in reset. `BUSY` cannot rise |
| `BUSY` shorted to ground | A solder bridge or the wrong pad |
| **The header off by one pin** | JP1 is `RST NSS MOSI MISO SCK BUSY GND` — one step down puts `GPIO10` on ground and `GPIO5` on `NSS` |

The third would explain everything at once, and one continuity measurement
verifies it: **`JP1 RST` ↔ `C3 GPIO5`.** If the counterpart is `GPIO6`, the
matter is settled.

#### Retracted: the `BUSY` joint was not open, and 353 kΩ was the right reading

This used to say that `JP1 BUSY` ↔ `C3 GPIO10` measured 353 kΩ and is
therefore open. **That was a misread measurement.** The reading was `BUSY`
**against ground**, i.e. the exclusion test that checks the header is not
off by one — and 353 kΩ is its correct result. The header pins were measured
separately and were fine.

The error is worth learning from, because it was not a measurement error but
a reading error: two measurements were given in sequence in the same list,
and the answer was taken to belong to the first. **Always ask which two
points were measured before building a claim on a reading** — an electrical
conclusion is only as good as the knowledge of where the probes touched.

A header pin is moreover continuous brass and conducts by friction alone
with no solder. **A kilo-ohm reading across a header pin would not have
meant a bad joint but a missing pin** — and that reasoning too should have
been checked before it was written into an instruction.

One observation stands as a design note even though it was not the fault:
when `GPIO8` and `GPIO9` are pulled out, `GPIO10` is left alone in the
header behind two empty positions with no support from its neighbours. That
is a place worth checking first, not a place anything is known about.

#### And the cause was two dead pads in the C3

All nine connections were eventually measured good, and `BUSY` still did not
rise. The fault was found when **ESPHome was told to drive the pins high
unconditionally**, with no NFC component:

```yaml
switch:
  - platform: gpio
    pin: GPIO5
    restore_mode: ALWAYS_ON
```

| Pin | Row | Reading |
|---|---|---|
| `GPIO1` `GPIO4` `GPIO7` `GPIO8` `GPIO9` `GPIO20` `GPIO21` | both | **3.3 V** |
| **`GPIO5`** `RST`, header position 1 | header | **100 mV** |
| **`GPIO6`** `NSS`, header position 2 | header | **100 mV** |

Seven pins rise, two do not — and those two are the header's first, i.e. the
ones that took the most heat. **The break is inside the C3 between the pad
and the die.** Continuity from `JP1` to the pad passes, there is 860 kΩ to
ground, and there is no bridge between neighbours — all the earlier
measurements were made correctly and still told the wrong story, because
they measured the *outer* side of the pad.

**A load was excluded twice.** First by arithmetic: holding a 40 mA output
at 100 millivolts would require a three-ohm load, and a PN5180 input cannot
present one. Then experimentally — the owner cut the header pins, verified
the isolation was open and measured again: **the same 100 mV.** The
arithmetic was right, but the experiment was still the right thing to do,
because reasoning had fallen over more than once that evening.

**And the first choice of replacement pins was wrong.** `GPIO20` and
`GPIO21` were chosen on the grounds that they are not strapping pins and
that UART0 is free, because the logger uses `USB_SERIAL_JTAG`. That
reasoning was right on paper and wrong in practice: **the boot stopped at
the line `Using HW SPI: SPI2_HOST`**, no `spi_device` line appeared at all,
and `safe_mode` counted the boot as unsuccessful.

Changing only the pins to `GPIO1` and `GPIO0` removed the symptom — the
wires were left untouched, so nothing else changed. **The mechanism has not
been verified**, and the empirical rule is enough: do not use the C3's UART0
pins for SPI control lines, even with the logger on USB.

The same experiment also excluded the other possibility: if the hang had
come from a new solder joint, it would have continued after the pin change.

**The fix was two enamelled wires rather than a board swap.** A dead pad is
an open circuit and disturbs nothing, so the old header pins can stay and
the header still carries the board via `GPIO7`.

**The method is the part that transfers elsewhere:** when the wiring
measures good and the device still does not answer, **drive every pin high
unconditionally and measure them against a control.** That separates a board
fault from a wiring fault in one build, and it does not rely on the driver
behaving as expected.

#### Resolved: MISO and SCK were crossed, and the diagram crossed them

**The module was never dead.** After the two wires were swapped in the
configuration, the PN5180 came up and started transmitting:

```
[D][PN5180:241]: Send data (len=3): 26 01 00
[D][PN5180:154]: Write Register 0x00: with AND mask …
[D][PN5180:549]: Get Transceive state...
```

`26 01 00` is an ISO 15693 Inventory — flags `0x26`, command `0x01`, mask
length `0x00`. The chip is initialised, in NFC-V mode and looking for a tag
in the field. The `qalcosonicnfc is marked FAILED` line disappeared from the
configuration dump at the same time, for the first time in the project.

**The cause was `MISO` and `SCK` soldered the other way round**, and they
were like that from the first joint — because
[`nfc-c3-mount.svg`](nfc-c3-mount.svg) drew the two wires crossing even
though the pads sit directly opposite each other at the same height. A
straight wire, which is what anyone would solder, produces `MISO`→`GPIO4`
and `SCK`→`GPIO3`. The diagram produced the crossing; the build did not.

The symptom matches exactly: the clock went into the module's `MISO`
**output** and the `SCK` **input** got no clock, so the chip could not
execute a command and could not raise `BUSY`. That is `Step 3 - Failed` in
one sentence.

**And no measurement made could have seen it.** Continuity was good on both
wires, there were no bridges, no shorts to ground, both pins drove 3.3 V —
every one of those tests passes when two conductors are simply swapped end
for end. **Continuity proves a conductor exists and that a signal gets
through; it does not prove the two ends belong together.** That is a third
level beyond the two this file already records.

The fix was two lines in the YAML, not an iron: on the C3 SPI goes through
the GPIO matrix and ESPHome takes the pins from the configuration. The
diagram was redrawn as two horizontal lines to match.

**This retracts the conclusion below**, which was reached the previous
evening: the module was named as the only remaining suspect, and a
replacement was about to be ordered. It was innocent.

#### What the wiring investigation had established



Everything measurable was measured, and **every result is good**:

| | How verified |
|---|---|
| `JP1`'s pin order | the module's silkscreen |
| The C3's row map | the board vendor's pinout diagram |
| Counting direction | `JP1` 1 and 2 gave 5 V and 3.3 V |
| `RST` → `GPIO1`, `NSS` → `GPIO0` | **the pin drives and the wire carries** — 3.3 V at both ends |
| `MOSI` → `GPIO7`, `SCK` → `GPIO4` | the pin drives, continuity |
| `MISO` → `GPIO3`, `BUSY` → `GPIO10` | continuity |
| `+5V`, `3.3V`, `GND` | voltages at the pads |
| Shorts to ground | `GPIO5` 860 kΩ, `BUSY` 353 kΩ |
| Neighbour bridges on `JP1` | `3↔4` 2 MΩ, `4↔5` `5↔6` `6↔7` `7↔8` all open |

(The `GPIO1`/`GPIO0` row is the first board's repair wiring. On the
replacement board `RST` and `NSS` are back on `GPIO5` and `GPIO6`.)

**Specifically what a continuity measurement would not have told** was done:
the control lines were driven high unconditionally with ESPHome's `gpio`
switches and measured at both ends. That separates "a conductor exists" from
"a signal gets through" — and it was exactly that which revealed two dead
pads no other measurement found.

**The PN5180 has not answered once in the whole project.** Every time it has
been measurable, something else has been broken: first the dead pads, then
the UART0 pins' hang. Now both are gone and the module still does not
answer.

That is not proof of a dead module, but it is the only remaining explanation
— and it cannot be tested without a second module or a second host.

#### Two unmeasured connections remained

Verified were four header pins and three voltages. **`MISO` → `GPIO3` and
`SCK` → `GPIO4` were the only ones not checked in any way.**

And `SCK` fits the symptom exactly: with no clock the PN5180 does not clock
the command in, executes nothing and does not raise `BUSY`. `MISO` would not
produce the same — a broken return line would give rubbish but `BUSY` would
still move, and the fault would show only later.

(Both were subsequently measured good.)

### The meter has been read

On day 2 at 17:17, with the board held against the meter's coil, the whole
chain worked end to end for the first time:

```
Inventory successful, UID=…
M-Bus Checksum OK (calculated: 18, received: 18)
Water Usage: 255.547 m³        Water Usage (Only Negative): 1.718 m³
Water Temperature: 15.1 °C     External Temperature: 18.0 °C
Battery Percentage: 91 %       Operating Time: 847 days
Error Flags Raw: 00 00 00 00
```

**Four things worth keeping from it.**

**One read takes 1027 ms.** That is the measurement this file has been
asking for since the polling budget was first written, and it settles the
interval:

| Interval | Reads/day | Consumption | Of assumed budget |
|---|---|---|---|
| **15 min** | **96** | **98.6 s/day** | **~250 %** — chosen |
| 1 h | 24 | 24.6 s/day | 62 % |
| 2 h | 12 | 12.3 s/day | 31 % |
| 3 h | 8 | 8.2 s/day | 21 % |

**Totals are correct at any of these**, because water is cumulative. What
changes is how lumpy the hourly graph looks, since Home Assistant computes
statistics per hour — and at 15 min each hour has four samples rather than
one.

### The interval was set past the budget on purpose

Two hours was chosen first, and the reasoning was about uncertainty rather
than arithmetic: **the 20 min/month credit is a general figure, not measured
from this meter**, 1027 ms is a single sample, and if both were 30 % out the
wrong way an hourly interval would already be over. A threefold margin
covered that.

**That reasoning was turned around by a working counter-example.**
`kosla-dev/qalcosonic-w1-nfc-reader` reads this same meter with this same
component **every 300 s.** By the arithmetic above that is 288 reads a day,
about 148 min/month — **seven times the assumed budget** — and it is a
finished, running build with no reported trouble.

Both cannot be true. Either the credit is much larger than 20 min/month, or
it is not consumed the way this file assumed — the plausible candidate being
that it meters something other than wall-clock transaction time.

**So the budget became the weakest number in the chain, not the interval**,
and a margin defended against a number that may be wrong protects nothing.
It only postpones finding out. Fifteen minutes is deliberately inside what a
working build already does and still well short of it.

**What makes this safe is the failure mode, not the margin.** If the credit
does run out, the interface locks until the hour turns: nothing breaks, no
setting is lost, and `Consecutive read errors` rises. That sensor is the
instrument — **a month at zero measures the credit; a month of climbing sets
the interval.** Either outcome replaces an assumption that has stood
unverified since the budget was first written.

The bench value of 2 min stays out: 720 reads a day is another sevenfold on
top of this, and it would be guessing again in the other direction.

**The Meter ID is not the nameplate serial.** The repo's placeholder was an
assumption from the nameplate and it was wrong. The real number stays out of
this file because the repo is public — but the rule holds once more: **the
device's own utterance beats the table.**

**The tag is powered by the field.** `EH_EN=1, EH_ON=1, FIELD_ON=1,
VCC_ON=1` — the ST25 harvests energy from the reader, which is why the read
works at all without touching the meter's battery beyond the communication
credit.

**And the error flags are all zero**, which is the first independent word
from the meter that nothing is wrong with it.

#### What the read did not answer, and why it no longer matters

**The component reads the M-Bus data block, not the meter's
configuration.** Radio state, the `wMBus T1` and `wMBus S1` flags and the
schedule masks live in the meter's own settings memory, reachable only
through the manufacturer's protocol — which is what Axilink does, and that
route is still closed.

So three of the four questions this project was built to answer are still
unanswered from the meter's own mouth.

**One of the four is answered, and it closes a hypothesis.** Total
consumption is 255.547 m³ over 847 days of operating time, so the 10-litre
threshold was passed two years ago: **transport mode is long released.**
Hypothesis 2.2 is dead — the radio is not off because the meter is still
factory-fresh.

It also strengthens the other conclusion. The meter is alive and healthy —
error flags zero, battery 91 % — and 36 hours of listening on 868.95 MHz
still produced nothing. "wM-Bus is switched off" is a better explanation now
than it was when the meter was silent for all we knew.

**But the question has become moot, and that is worth saying plainly.** The
radio state only ever mattered as a route to the readings. The readings now
arrive by another route:

| | |
|---|---|
| Is wM-Bus on | **No longer matters** — the values come the other way |
| The AES-128 key from the utility | **Not needed** |
| The transmission window | **Does not apply** |
| Dismantling the radio node | It can go. Its only job was this same data |

The only remaining reason to ask the water utility is curiosity, and it
costs calendar time for something already in hand.

**The alignment was found by hand, not by polling** — as the rationale here
prescribed. Failed inventories cost no credit, so the search was free.

### OPEN PROBLEM: the assembled node will not stay on Wi-Fi

Read this section first if you come back to this. Everything below it is the
working-out, including several retractions.

**The symptom.** The node associates occasionally and mostly does not.
Failures are `Auth Expired`, `Authentication Failed`, `4-Way Handshake
Timeout` and `Handshake Failed`, in no particular order. Scans are normal
and the access point is audible at −53 dB. **The device hears the access
point; the access point never completes the handshake.**

**The record of when it has been on the network:**

| When | Board | Stage 2 | `power_save_mode` | Network |
|---|---|---|---|---|
| after soldering, day 1 | first | out | no | worked, on the 6th round |
| day 1, 14:36 | first | active, component FAILED | no | worked |
| day 1, isolation test | first | out | no | worked |
| day 1, 15:32 and 17:25 | first | active, FAILED | NONE | worked |
| day 2, 10:21 | second | out (pin test) | NONE | worked |
| **day 2, 12:29 and 12:31** | second | **active, component reading** | no | **worked** |
| day 2, 13:xx onwards | second | out, then active | no | never again |

**There is no consistent factor among the successes.** It has worked with
the component disabled, with it present and failed, and with it actively
reading. It has failed with the component disabled.

**The one line that stands out is 13:xx.** Everything before it worked at
some point; nothing after it has worked at all, in any configuration. The
only event in between was carrying the board to the meter and back.

**The antenna is excluded too, and the scan results say so.** Three access
points are visible and the strongest reads −61 dB. Attenuation is the same
in both directions: an antenna detuned badly enough to kill transmission
would show the access points tens of decibels weaker than they are. It
does not.

To leave reception at −61 dB while stopping transmission entirely, the loss
would have to be 30–40 dB — and then the scan could not look like this. The
hypothesis has now fallen twice from different directions: the assembly
worked at 12:29 with the same geometry, and the scans are healthy.

**So foil under the C3, a taller header or a u.FL board would all fix a
fault that is not there.** Adding foil would in fact make things worse: a
conductive sheet a few millimetres from a PCB antenna detunes it, shorts the
near field and reflects power back. The one useful spacing for a reflector
is a quarter wave, about 31 mm at 2.4 GHz, which is not a few millimetres
and not this geometry.

**Excluded by measurement, not by argument:**

| | How |
|---|---|
| The board | two different C3s, same symptom |
| Signal, distance, the meter's metal | `Auth Expired` at −53 dB standing next to the access point |
| Power source | the same laptop USB throughout |
| `power_save_mode: NONE` | removed, no change; it was never a fix |
| Transmit power | `output_power: 8.5dB`, no change |
| Supply shorts | `5V ↔ GND`, `3V3 ↔ GND`, `5V ↔ 3V3` measured open repeatedly |
| Loose wiring | inspected |
| Resets and brownouts | priority decayed to −15 within one boot, no banner in between |
| The antenna, as **attenuation** | access points visible at −30 dB; a 30–40 dB loss cannot hide behind that. **Mismatch is a separate question and is not excluded** — see below |
| A client limit on the SSID | a phone joins `IoT` on request — the network does accept new associations |
| **The network** | **properly excluded**: a phone hotspot — independent hardware, sole access point, −30 dB — gives the same `Auth Expired` six times running |
| The PN5180 itself | answers, initialises, drives the RF field, issues inventories |
| A static IP | tried, no change — and it **cannot** help: it removes DHCP, which is downstream of the handshake that fails |

**Two explanations were reached and both were retracted:** that the PN5180's
ground plane detunes the C3's antenna (killed by the 12:29 success with the
same geometry), and that the supply dips during transmit bursts (killed by
the transmit-power cut changing nothing).

**The ESP-IDF version was the last candidate and it is dead too.** The
reasoning was that this node is the only one built on ESPHome 2026.9.0 with
ESP-IDF 5.5.5, and that the others were flashed months ago and never
re-associate, so they never exercise the current supplicant.

**That premise was wrong, and the capture logs in the repo root disprove
it:**

| Node | ESPHome | Compiled |
|---|---|---|
| onewire | **2026.9.0** | 21.9.2026 |
| stiebel (`wpc-c3`) | **2026.9.0** | 22.9.2026 |
| axioma-nfc | 2026.9.0 | 24.9.2026 |

All three are on the same version, and the first two were flashed days ago —
so they re-associated on this same ESPHome and the same IDF, and they work.
onewire is a C3 in the same room as the meter.

**Same chip family, same ESPHome, same supplicant, same network, same room —
one works and one does not.** That is as tight a comparison as this project
can make, and it leaves the difference inside the axioma-nfc node itself:
its configuration or the PN5180 attached to it. Both have been tested, and
neither explains it.

A phone also joins `IoT` on request, so the access point accepts new
associations.

#### The configurations were compared line for line, and the one difference is innocent

onewire is a C3 in the same room, on the same ESPHome version, and it
associates without trouble. Comparing the two configurations, **everything
before the sensor blocks is identical** — board, framework, `api`, `ota`,
`wifi`, `captive_portal`, and the same shared secrets — with one exception:

```yaml
logger:
  level: DEBUG
  hardware_uart: USB_SERIAL_JTAG    # only in axioma-nfc
```

That suggested a mechanism with a feedback loop, which would have explained
why the fault got worse rather than staying constant: the log goes out over
USB and there is a great deal of it, the four-way handshake's timeouts are
in the hundreds of milliseconds, a failed association produces more log
lines, and so the next attempt is more likely to fail.

**Lowering the level to `INFO` — over 90 % less output — changed nothing.**
So the volume is not the cause, and by extension neither is the mechanism.

That leaves the two configurations equivalent in every respect that could
plausibly touch association, and the fault still follows one of them.

**Nothing is left worth guessing at.** The useful move is below.

#### The static address was tried and removed

`manual_ip` at `192.168.1.42` with `use_address` to match. **No change**,
which is what the mechanism predicted: a static address removes DHCP, and
DHCP is downstream of the handshake that fails. The prediction was written
into the configuration before the test, so this is a confirmed expectation
rather than a result.

The reason it was worth flashing anyway was observability, not repair. **The
observation method changed when `hardware_uart` was removed** — the serial
log is gone, the node is watched from the server, and mDNS has already
produced one wrong answer here, with `esphome` resolving a stale address
after it had been changed on the device. A fixed address reduced the
question to `ping`.

**It is removed again**, for a reason that matters more than tidiness: the
next test moves the node to a second SSID, and **a second network may be a
different subnet.** An address from the old one would produce an unreachable
node whose symptom is indistinguishable from the fault under investigation.
That would not waste the test; it would corrupt it.

The secondary reason is the one that removed `power_save_mode: NONE`
earlier: a setting that fixes nothing is read later as a choice.

#### The network was excluded as a whole, which is not the same as excluded

**The next test points this node at a second SSID.**

The network has been ruled out four times, each time on the owner's evidence
that other ESP32-C3 nodes run on it faultlessly — `onewire` among them, a C3
in the same room. That argument is sound and it is not withdrawn.

**But it excludes the network, not an interaction between this node and one
particular access point**, and the difference is the whole remaining
question. `onewire` proves the SSID carries a C3. It does not prove that
whatever *this* node does during the four-way handshake is tolerated by the
access point it happens to pick. Nothing measured so far separates those
two, because every measurement has been taken against the same SSID.

A second SSID separates them for one flash and no soldering, which makes it
the cheapest untried thing left.

**One condition decides whether the result means anything: the second
network must be 2.4 GHz.** The ESP32-C3 has no 5 GHz radio, so a `…_5G`
name produces a node that never sees the access point — and that log is
indistinguishable from the fault being investigated. It would read as
confirmation and be nothing of the kind. This is the same error shape
recorded three times in this file: **a measurement that does not measure
what its title says.**

The credentials are `wifi_ssid2` and `wifi_password2` in the shared
`/config/secrets.yaml`.

| Outcome | What it means |
|---|---|
| **Associates and stays up** | The fault is an interaction with the first access point, not with the node. Everything above about antennas and supplies is beside the point |
| **Same failure** | The network is excluded properly this time, and the fault is inside the node — which is where the evidence already pointed |

Either answer is worth more than the last several flashes, because **this is
the first test whose two outcomes lead somewhere different.**

#### The network is excluded, and the test that did it was the third attempt

**A phone hotspot, its own SSID, 2.4 GHz, one access point and nothing else
in the scan. −30 dB. `Auth Expired` on six consecutive attempts.**

That is the cleanest measurement this problem has produced, and it took
three tries to get right:

| Attempt | Why it did not count |
|---|---|
| A second home SSID | Almost certainly the same physical access points — it varies the SSID configuration, not the hardware |
| The hotspot sharing that SSID | Three access points under one name and one credential; the node round-robins and attribution is lost |
| **The hotspot on its own name** | **Counts.** One candidate, independent hardware, no shared state |

A phone hotspot shares no firmware, no configuration, no client table and no
block list with the Deco or the MikroTik. **The network is now excluded in
the strong sense**, not on the owner's reasonable inference from other
nodes.

**And the configuration is no longer a difference either.** With
`hardware_uart` removed, this node's configuration is identical line for
line to `onewire` — a C3 in the same room that associates without trouble.
Same ESPHome, same chip, same configuration, an independent access point at
−30 dB, and one works and one does not.

**One difference remains: the PN5180 is attached.**

##### The symmetry argument excludes attenuation, not mismatch

This file has said the antenna is excluded because attenuation is
symmetric — reception at −61 dB rules out the 30–40 dB loss that killing
transmission would require. **That reasoning is sound for attenuation and
does not cover mismatch**, and the distinction was missed here.

Reciprocity applies to the antenna as a passive element. It does not apply
to **how the power amplifier behaves into a bad load.** Reflected power can
distort the transmitted signal so that frames arrive at the access point
corrupt, while the same antenna's reception loses only a few decibels.
Reception never experiences that nonlinearity.

So the accurate statement is: **attenuation is excluded; a mismatch that
corrupts transmission is not.** It fits the symptom exactly — the device
hears perfectly and the access point never gets a usable frame from it.

**This does not reinstate the antenna as the explanation.** The
counter-evidence stands and it is not weak: the assembly worked at 12:29
with this same geometry. But "excluded" was too strong, and both builds
known to work keep the radio off the module.

##### The next test needs no iron

There are spare C3s on the shelf. **Flash a bare one with this same
`axioma-nfc.yaml`, stage 2 commented out, and point it at the same
hotspot.**

| Outcome | What it means |
|---|---|
| Associates and stays up | The configuration and the access point are fine — the fault is the assembled node: the module, or its effect on the radio |
| The same failure | The fault is in the configuration or between ESPHome and this access point, not in the hardware |

**Earlier bare-board tests were run against the home network, not this
one**, so this is a new measurement rather than a repeat. It is also the
last one available without a soldering iron.

#### It does not have to be solved

What this node was built to answer is a one-off question: is `wMBus T1` on,
in which mode, what are the schedule masks, and has transport mode been
released. **The NFC side works and the serial port works.** A laptop at the
meter with a USB cable answers all four without Wi-Fi being involved:

```sh
cat /dev/ttyACM0 | grep -a --line-buffered -E "qalcosonicnfc|Water|Meter|Serial"
```

The component runs its read cycle with no network — that has been verified.
And the answer decides whether a permanent node is worth any further work:
if wM-Bus turns out to be switched on, the radio node is the right route and
this Wi-Fi problem never needs solving.

### Working notes: the Wi-Fi fault follows the PN5180

**State at the end of the second day.** The node does not stay on the
network once the PN5180 is attached, and everything else has been excluded
by measurement:

| Suspect | Status |
|---|---|
| The board | **out** — two different C3s, same symptom |
| Signal, location, metal | **out** — `Auth Expired` at −53 dB standing next to the access point |
| Power source | **out** — the same laptop USB throughout |
| `power_save_mode: NONE` | **out** — removed, no change. It was never a fix |
| The network | **out** — the owner's call, twice, and right both times |
| **The PN5180 being attached** | the one thing that tracks the symptom |

The symptom profile is consistent throughout: **the device hears the access
point perfectly and the access point never completes the handshake.** Scans
return −53 dB and every association dies in authentication. That is a
transmit-side failure, and transmission is the direction that tolerates
least.

#### Retracted: it is not the antenna either, and the timeline says so

The section below concluded that the C3's PCB antenna, sitting on the
PN5180's ground plane, is the cause. **That is wrong, and one line of the
timeline kills it:**

| Time | State | Network |
|---|---|---|
| 10:21 | bare C3 | worked |
| **12:29** | **soldered, component active** | **worked** |
| **12:31** | **read cycle running** | **worked** |
| 13:xx onwards | the same assembly | fails everywhere |

**The assembly worked soldered, with the component running.** The ground
plane was in exactly the same place then as now. If the copper were the
cause, 12:29 could not have happened.

So the variable is **the trip to the meter and back** — the only thing that
happened between 12:31 and the first failure. Something changed physically:
a wire, a joint, or the 330 µF and its legs, when the board was pressed
against the meter.

**What that implies for the transmit-power experiment below:** cutting power
did not help, which still argues against a supply dip being the *whole*
story — but a short created on the trip would load the supply in a way that
no software setting can compensate for, and that is untested.

**The measurement that would settle it needs no iron:** with USB out,
`5V ↔ GND`, `3V3 ↔ GND` and `5V ↔ 3V3` must all read open. A short there
would not stop SPI — the chip still gets a supply — but it would load the
same five volts the radio needs during a transmit burst. It is the first
explanation that covers both that it worked at 12:29 and that it does not
now.

#### The experiment that was read as separating antenna from supply

`output_power: 8.5dB` was flashed — a two-thirds cut in the transmit current
peak. **No change:** `Handshake Failed` and `Authentication Failed` at
−60 dB, exactly as at full power.

If the cause were a supply dip during the burst, cutting the burst would
have helped. It did not. And the controlled pair is complete:

| | |
|---|---|
| Bare C3, same network, same configuration | **associated immediately** |
| Same board with the module attached | does not associate |
| Transmit power cut to a third | **no change** |

**The cause is the antenna.** The C3's PCB antenna sits ~6 mm above a
70 × 39 mm board carrying a ground plane and a copper coil, which detunes it
and absorbs the radiated power. Reception survives that — the access point
is audible at −60 dB — but transmission does not carry.

It explains every observation of the two days at once: the device hears, the
access point never hears the device, and it makes no difference where in the
house it is or how close to the access point it stands.

**One more thing it ruled out:** the priority decay reached `-15` within a
single boot with no banner in between, so the board is not resetting. The
serial port dropping repeatedly is USB CDC behaviour, not brownouts.

**The fix is mechanical.** Three options, middle one recommended:

| | |
|---|---|
| A taller header | A few more millimetres of air. The plane is large, so unlikely to be enough |
| **The C3 off the module's footprint**, 10–15 cm of wire | Removes the cause. SPI tolerates it at 2 MHz, as this file already records |
| A board with u.FL and an external antenna | Surest, but needs a new board |

**Two mechanisms were open and have now been separated:**

| | |
|---|---|
| **Ground plane** | a 70 × 39 mm board with a copper coil sits ~6 mm under the C3's PCB antenna. That detunes it and absorbs radiated power. Reception survives it; transmission does not |
| **Load** | the module draws from the same supply that drives the C3's radio, and a dip during a transmit burst kills the handshake |

**The experiment that separates them is to lift the module's `+5V` and
`3.3V` while leaving it physically in place** — the ground plane stays, the
current goes. It is safe with stage 2 commented out, because nothing then
drives the module's pins.

One earlier experiment looked decisive and was not: commenting out stage 2
leaves `RST`, `NSS`, `MOSI` and `SCK` **floating**, so the module sits in an
undefined state rather than an idle one. That test separated active driving
from undefined, not electrical from radio.

**Untried and needing no iron:** `wifi: output_power: 8.5dB` lowers the
transmit current peak by roughly two-thirds. If the cause is a supply dip it
may get through where full power does not; if the cause is detuning it will
not. It is free, and it might also be the fix.

If the ground plane wins, the fix is mechanical: move the C3 off the
module's footprint — SPI at 2 MHz tolerates 10–20 cm of wire — or use a
board with a u.FL connector and an external antenna.

**And the NFC side is finished.** The PN5180 answers, initialises, turns on
the RF field and issues ISO 15693 inventories. Nothing on that side is
waiting for anything except the board being held against the meter's coil.

### And the Wi-Fi fault is not in the network

A long list of network hypotheses had accumulated here: the MikroTik's
`disable-pmkid` and `management-protection`, the Deco's `WPA/WPA2` mixed
mode and TKIP group key, the access point's client table,
`power_save_mode: NONE`. **All of them are unnecessary, and the owner cut
them off with one sentence: several other ESP32-C3 nodes work faultlessly on
the same network.**

That is stronger evidence than any inference from a log. If the network
broke a C3's association, it would break all of them.

**The common factor is this particular board**, and there is an independent
finding about it: two GPIO pads are dead and seven others work.

**But "the board does not stay on the network" is the wrong phrasing, and
the owner corrected it: it stays, when the PN5180 is not in operation.** It
has been on the network steadily both without the NFC component and after
the component failed — i.e. whenever the module is not being driven.

Then it is not a faulty radio but an **interaction**, and that points at the
shared supply: the transmitter side peaks at hundreds of milliamps from the
same five volts that drives the C3's radio, and there is no buffer between
them on the board.

**The capacitor is now fitted** — 330 µF / 25 V between `+5V` and `GND` —
and it did not change the PN5180's result: `No communication` continues.
That was to be expected, because a register read draws no current. Its real
test is still ahead: whether network drops appear once reads start
happening.

**And it put that 100 µF back on the list.** This briefly said it fixes no
known fault; if the instability follows the module's operation, it is
exactly the fault a capacitor fixes. And it would explain why swapping the
power supply did not help: **the dip happens on the board, not in the
source.**

Testable only once the module answers and reads come regularly — then one
can see whether the drops coincide with read attempts.

The symptoms fit: scanning and RSSI are fine, but association fails at the
handshake and the fallback AP is not visible on a phone. That is the split
between reception and transmission, and transmission is the direction that
tolerates least.

**`power_save_mode: NONE` stays in place** but its justification is now a
hypothesis: it was added when one association succeeded right afterwards,
and that was read as proof. On mains power the cost is nil, so it may stay —
but this section says out loud that it is not a verified fix.

**And from this follows a lesson that is now in this file four times:** when
two hypotheses from the same source have fallen, do not propose a third from
that source. Get a new source — or ask the owner, who has years of operating
history for devices whose logs cover hours.

#### Consequence: the board is replaced

The first C3 was good enough for verifying the PN5180, and it was on the
network steadily whenever the module was not being driven. **Established
faults on it are therefore one and not two: two dead pads**, and they were
worked around with wires.

Replacing the board was still the next experiment — not because the radio is
broken, but because **the SPI block is the only part the measurements do not
cover**, and a manufacturing defect has already been demonstrated on that
particular board.

The replacement passed the pin test on all seven pins, so the nine
connections move to it — and then `RST` and `NSS` go back to `GPIO5` and
`GPIO6`, because the repair wires were for that one board's dead pads and
not part of the design.

**Test a new board's pins before you solder.** See README, step 6.5.

### Comparison with the other projects that do this

Two independent projects read this meter with a PN5180 and ESPHome, and both
were checked against ours.

**[kosla-dev/qalcosonic-w1-nfc-reader](https://github.com/kosla-dev/qalcosonic-w1-nfc-reader)
is the same build, finished.** Same meter, same component, **the same commit
pin `bed6773`**, a custom adapter PCB and a printed mount. It confirms two of
our choices and differs in one that matters.

| | kosla-dev (works) | here |
|---|---|---|
| Board | **`seeed_xiao_esp32c3`** | C3 SuperMini |
| **Antenna** | **u.FL, external on a pigtail** | **PCB antenna on top of the module** |
| logger | `INFO`, **no `hardware_uart`** | had `USB_SERIAL_JTAG` |
| `update_interval` | **300s** | **15 min** — set toward this; see above |
| `power_save_mode`, `output_power` | neither | neither |
| Component and commit | same | same |

**The XIAO ESP32-C3 has no PCB antenna at all** — it has a u.FL connector
and ships with an antenna on a lead. So in the one known working build of
this exact project, **the antenna is physically away from the PN5180.**

That is not evidence that our antenna is the fault — reception at −61 dB
from three access points argues against it, and that argument stands. But it
is worth recording plainly: **nobody has demonstrated this working with a
PCB-antenna board sitting on the module.** If the Wi-Fi problem is ever
worth spending money on, a XIAO ESP32-C3 is the board that is known to work
here, not a guess.

One observation without an explanation: **kosla-dev uses `GPIO20` for `BUSY`
and `GPIO21` for `SCK`** — the two pins that hung the boot here at
`Using HW SPI: SPI2_HOST`. Different physical pads on the XIAO, the same
GPIO numbers. Recorded as an observation.

**`hpuac/esphome-qalcosonic-e3`** does the same for the QALCOSONIC E3 heat
meter, and **`JohnMcLear/esphome_pn5180`** and
**`bluenazgul/esphome_pn5180_tag_reader`** are generic PN5180 components for
ESPHome. None of them is closer to this build than kosla-dev's.

#### A third build, and every working one keeps the radio off the module

**[Wolfrax/esp32_watermeter](https://github.com/Wolfrax/esp32_watermeter)**
is a different meter — a Sagemcom Siconia WM20-L with an `ST25DV04K-I` tag —
but the same chip and the same protocol, and it is in production and
confirmed end to end. It is not an ESPHome project at all: bare ESP-IDF with
its own `wifi.c`, a ported PN5180/ISO 15693 driver, and MQTT to a broker.
Its author considered ESPHome and chose against it.

What it contributes here is mechanical. **The ESP is an ESP32-C6-DevKitC-1
on the end of a ribbon cable**, colour-coded per pin, with the PN5180 a
separate board. Nothing is stacked.

That completes a pattern worth stating plainly:

| Build | The radio relative to the module | Works |
|---|---|---|
| kosla-dev | u.FL, antenna on a lead | yes |
| Wolfrax | its own board, on a cable | yes |
| **here** | **PCB antenna ~6 mm above the module** | no |

**This is not evidence for the antenna hypothesis.** That one fell to
measurement and stays fallen: three access points are audible at −61 dB, and
attenuation is symmetric. A population of two proves no mechanism.

But it is worth recording as what it is: **among builds known to work, none
has this geometry.** If money is ever spent on this problem, that is the
direction with a precedent behind it — and both precedents agree, from
different chips and different software.

One detail that does not transfer: Wolfrax wires `PD/CE` to a GPIO so the
firmware can power-cycle the chip's logic core out of a stuck state without
a physical reset. **This module has no such pin.** `JP1` is
`+5V 3.3V RST NSS MOSI MISO SCK BUSY GND GPIO IRQ AUX REQ` — a different
board revision, and the recovery trick is not available here.

#### The component's own origin reads no more than we do

**[MrGoodbody/AxiomaQalcosonicW1NFCReaderAndroid](https://github.com/MrGoodbody/AxiomaQalcosonicW1NFCReaderAndroid)**
is where `esphome_qalcosonicnfc` came from: an Android proof of concept for
this exact meter, which dbmaxpayne ported and which MrGoodbody now links to
in place of finishing an ESP version.

It is open source, so **unlike Axilink Lite it could be built and sideloaded
onto the phone.** That sounds like a way back into the question the ESPHome
read cannot answer, and it is not.

Its whole source is `MBusParser`, `MBusTelegram`, `CounterEntry` and the NFC
callbacks. **It reads the same M-Bus data block we already get** — no
configuration registers, no radio flags, no schedule masks.

So the configuration route is now closed from two directions rather than
one: the manufacturer's app is behind a password, and the only open
implementation does not attempt those registers at all. **Radio state, the
`wMBus T1`/`S1` flags and the schedule masks are obtainable from the water
utility or not at all** — and per "What the read did not answer", the
question is moot anyway.

**`egonladd/Qalcosonic-W1`** and **`egonladd/w1-Qalcosonic`** are not
implementations but questions posted as repositories — *"I have a LoRa
device called Qalcosonic W1 … I can see the payload, in HEX"*. No code.
Recorded only because they are a second instance of this meter in LoRaWAN
use, which is the configuration inferred here.

### The upstream issue tracker, checked

**No issue anywhere mentions Wi-Fi trouble with this component.** Three
match observations made here:

| | |
|---|---|
| **#28**, open | `NSS` is left asserted when the `BUSY` wait times out, because `transceiveCommand` returns from the error path before deasserting it. **This is the same bug found here by reading the source** — see the retracted `BUSY` section above |
| **#27**, open | every second cycle fails with `No card detected`, independent of the interval. If that starts happening here it is not our wiring |
| **#23**, open, with PR #24 | `At least one of 'id:' or 'name:' is required`. **This is our validation failure**, known upstream and unfixed. Naming `timepoint_sensor` is the right workaround |

**#25** is the one to watch if reads ever start crashing the board: an
unbounded wait for `RX_IRQ_STAT` in `issueISO15693Command` blocked the main
loop until the watchdog fired.

### The component's schema, verified from the source

`esphome_qalcosonicnfc`'s keys were read from
`components/qalcosonicnfc/__init__.py` rather than from the README, and
**three things out of four were wrong in the first guess:**

| | Guess | Reality |
|---|---|---|
| Component name | `qalcosonic_nfc` | **`qalcosonicnfc`**, no underscore |
| Pin keys | `cs_pin`, `busy_pin`, `reset_pin` | **`pn5180_nss_pin`**, `pn5180_busy_pin`, `pn5180_rst_pin` … |
| Separate `spi:` block | needed | **not needed** — `AUTO_LOAD` includes `spi` and the component takes all six pins itself |
| Pins | from the diagram | right |

The fourth row is the one that matters: **the hardware was right and only
the software was wrong.** The soldering was done before the keys had been
checked, and that was safe precisely because of this — the pins come from
the diagram and the wiring, not from the component's documentation.

`update_interval`'s default is **60 s**, which would burn a month's
communication credit in half a day. It has to be set explicitly.

**The source is pinned to commit `bed6773`** rather than to a branch. The
reasoning is the same as in the radio node and recorded three times in this
repo: `@main` is a moving reference, and the same YAML can build differently
without anything changing in the repo.

The same lesson for the third time in this file, and this time it saved a
build: **the source says in a second what the README does not.**

#### The build produces a couple of dozen warnings, and two are not noise

Most are `-Wformat=`: on RISC-V `uint32_t` is `long unsigned int`, so `%u`
and `%X` warn even though the output is correct — both consume 32 bits. They
say the component was written with another architecture in mind, not that
anything is broken.

**These two are a different matter:**

```
qalcosonicnfc.cpp:353: 'snprintf' output may be truncated
  snprintf(str_id_number, sizeof(str_id_number), "%08u", id_number);
  output between 9 and 10 bytes into a destination of size 9
```

**A Meter ID longer than eight digits is truncated.** The buffer is nine
bytes, i.e. eight digits and a terminating zero, but a `uint32_t` can be ten
digits. This meter's number is eight digits, so it does not hit — but if
`Meter ID` or `Serial number` ever looks wrong, this is why, not the read.

```
qalcosonicnfc.cpp:489: suggest parentheses around arithmetic in operand of '|'
  int32_t year = (buf[2] >> 5 | (buf[3] >> 1) & 0xF8) + 2000;
```

`&` binds more tightly than `|`, so the expression is
`(buf[2]>>5) | ((buf[3]>>1) & 0xF8)`. That is probably the intent — a
seven-bit year field from two bytes — but **check the timestamp from the
first successful read** rather than assuming it. That is cheap right then
and expensive after a month of looking at it.

Both are worth reporting upstream; the project's language was switched to
English partly so that they can be copied straight into an issue.

#### Two things the schema does differently from what one would expect

**1. An entity is not left out by not mentioning it.** Every sensor has
`default={ CONF_NAME: "…" }`, so **an omitted block is still created with
its default name.** The listing therefore does not choose which entities are
created, only which ones get a name of our own; the device brings about
thirty entities into Home Assistant either way. An unwanted one is hidden
with `internal: true`, not by silence.

**2. `timepoint_sensor` is required although it looks optional.** It is the
only one whose default is an empty `{}`:

```python
cv.Optional(CONF_TIMEPOINT_SENSOR, default={}): cv.Schema({
    cv.Optional(CONF_NAME, default="Time point"): cv.string,
    cv.Optional(CONF_TIMEZONE): validate_tz,
}).extend(
    text_sensor.text_sensor_schema()
),
```

The name's default is in the inner schema, but `.extend()` redeclares the
same key without a default and overwrites it. The result is a block with
neither `id` nor `name`, and validation fails with:

```
At least one of 'id:' or 'name:' is required!
```

**The error fires on the default configuration**, i.e. the component does
not validate as shipped. And the error message does not say which block it
concerns unless the whole output is read — the same class of fault as
elsewhere here: the symptom points far from the cause.

### Alignment without the printed case

The upstream project has a 3D-printed case that aligns the antenna to the
meter's coil. **It is not used**, and the reason is better than taste: the
case locks the position before it has been verified. The board has four
mounting holes, and a cable tie or thin double-sided tape allows the
alignment to be adjusted after the first successful read — a case does not.

**The orientation follows from physics and is not a matter of taste:**

- **Flat against the surface.** NFC is inductive coupling: the field passes
  through the plane of the coil, so the board does not go on its edge.
  Rotation in the plane means nothing, because both are loops rather than
  dipoles.
- **Antenna end over the coil, header end away.** Only the right ~40 mm of
  the board is antenna, and with the header pointing away the wires leave to
  the side rather than folding over the coil.
- **Smooth side towards the meter.** Components lift the board millimetres
  away and the coupling weakens quickly with distance.
- **No metal in between or behind the antenna.** A conductive surface damps
  the field and detunes the antenna. A cable tie is plastic; a bracket may
  not be.
- **Support from the antenna end, not the header end.** See the next
  section: the board may stay clear of the surface at the left end, but the
  coil end may not.

### The flatness requirement covers the antenna area, not the whole underside

This first said, absolutely, *"do not solder on the smooth side"*, and that
is too strict. The correct rule is narrower and follows from what the
coupling actually requires:

> **Under the antenna the underside has to be smooth. Elsewhere it does not
> matter.**

The coil is the board's right ~40 mm. The left third is more than 30 mm from
it, and a solder blob there **does not lift the antenna but tilts the
board** — half a millimetre over forty millimetres is less than a degree.

**But that only holds if the board is supported at the antenna end.** If the
fixing presses at the left end, the tilt reverses and lifts the coil away
from the meter — i.e. produces exactly the fault being avoided. The cable tie
or tape therefore goes **on the antenna side**, and the left end may stay
clear.

A practical benefit follows: **the PN5180's top side never needs to be
touched with an iron.** The header is pushed into the holes from above but
soldered from below — the normal through-hole way — and the jumper wires are
soldered from below as well. All nine connections are made from one side,
and they fit in the left third.

### Nine connections, eighteen joints

There are nine connections and each has two ends: one on the PN5180, one on
the C3. There is no such thing as "the C3's own connections" — only the
route differs.

| | Route | PN5180 end | C3 end |
|---|---|---|---|
| `RST` `NSS` `MOSI` `BUSY` | header pin | from below | to the C3's pad |
| `MISO` `SCK` `+5V` `3.3V` `GND` | enamelled wire 0.2–0.3 mm | from below | to the C3's pad |

**The assembly order is forced**, because there is no getting an iron under
the C3 once it is in place:

1. Five enamelled wires from below, into the left third
2. The header into four pads, soldered from below — tape the header down
   before turning the board over
3. The C3 onto the header from above, the wires' other ends into its far row
4. **100 µF between `+5V` and `GND`**, next to the PN5180
5. Strain relief with glue or a cable tie

The fourth step was missing from the first version of this list, even though
it appears on this file's own list of things that easily go wrong. There are
nine connections and they are easy to enumerate; the capacitor is not one of
them and so falls off the list. **And its absence looks like a network
fault**, because a supply dip during transmission produces a
`4-Way Handshake Timeout` and nothing that points at power.

Wires before the header, because the header's pins protrude underneath
exactly where the thin wires need to be routed.

### Find the coil by looking, not by polling — but trying by hand is cheap

This briefly said the position must not be found by trial at all. **That was
too blunt.** The difference is between automatic and by hand:

| | Credit out of 1200 s/month |
|---|---|
| Ten hand-triggered test reads | ~20–30 s, under 3 % |
| A polling loop hunting for a hit | a month in minutes |

Trying is therefore not what burns the budget; **a loop left running while
you search** is. Switch automatic polling on only once the alignment is
found and the board is permanently fixed.

The cheapest order:

1. **Locate the coil by looking** — zero credit. The cover often has a
   marking or a moulded circle; the coil is typically near the display
   behind the plastic; and **the W1's FCC filing's internal photographs**
   are public and show it directly. That is the same source the upstream
   author located it from.
2. **Fix it loosely and read once.**
3. **If it misses, move a centimetre.**

Only once a read succeeds is the fixing made permanent and polling switched
on.

### Wiring

**Both ends are verified from a source, not from inference.**

`JP1`'s order was read from **the module's own silkscreen** — it is legible
in the product photo at the repo root, starting from the `JP1` marking:

```
+5V  3.3V  RST  NSS  MOSI  MISO  SCK  BUSY  GND  GPIO  IRQ  AUX  REQ
```

It was also confirmed by measurement: pins 1 and 2 gave 5 V and 3.3 V, so
the counting direction is right.

The C3's row map comes from the board vendor's pinout diagram: the header
row from USB-C onwards is `GPIO5` `GPIO6` `GPIO7` `GPIO8` `GPIO9` `GPIO10`
`GPIO20` `GPIO21`, the far row `5V` `GND` `3V3` `GPIO4` `GPIO3` `GPIO2`
`GPIO1` `GPIO0`.

**Upstream gives no pins for the C3 at all.** Its table is for an ordinary
ESP32 (`SCLK 18`, `MISO 19`, `MOSI 23`, `NSS 14`, `BUSY 16`, `RST 17`) and
`board: esp32-c3-devkitm-1` is commented out in the example. The pin choice
is therefore free, and this project's choice is based on the C3's free pins
— not on having been copied from anywhere.

Two diagrams, for different questions:

| | |
|---|---|
| [`nfc-c3-mount.svg`](nfc-c3-mount.svg) | where the C3 goes on the board, which connection is a header pin and which a wire |
| [`nfc-wiring.svg`](nfc-wiring.svg) | which signal goes to which pin, without the mechanics |

**The signal diagram had the wrong pin map after orientation A was fixed** —
`RST` `NSS` `MOSI` `MISO` still pointed at `GPIO3` `GPIO7` `GPIO6` `GPIO5`,
i.e. the first proposal. That is corrected. Two diagrams of the same wiring
are two places that can diverge, and this one diverged immediately — **the
table below is what decides if a diagram disagrees with it.**

**The chosen orientation is A: USB-C up, UART free.**

| JP1 | C3 | Route |
|---|---|---|
| `RST` | `GPIO5` | header pin |
| `NSS` | `GPIO6` | header pin |
| `MOSI` | `GPIO7` | header pin |
| `BUSY` | `GPIO10` | header pin |
| `MISO` | `GPIO4` | enamelled wire |
| `SCK` | `GPIO3` | enamelled wire |
| `+5V` | `5V` | enamelled wire |
| `3.3V` | `3V3` | enamelled wire |
| `GND` | `GND` | enamelled wire |

**Four pins are pulled out of the header** before assembly: `GPIO8` and
`GPIO9` are strapping pins, `GPIO20` would land on ground and `GPIO21` on an
unused pad.

The pins in use are `3, 4, 5, 6, 7, 10` — the same safe six as from the
start, only for different signals. Strapping `2, 8, 9`, USB `18/19` and
UART0 `20/21` all stay free.

**Do not use `GPIO20` or `GPIO21` as replacements** if a header pad turns
out to be broken. They hang the boot at `Using HW SPI: SPI2_HOST` — see "And
the cause was two dead pads in the C3". `GPIO1` and `GPIO0` on the far row
work.

**Rejected alternative B** would have turned the C3 so that USB-C points
towards the unused pads. That would cost UART0, because flipping mirrors all
eight pins and `GPIO20`/`GPIO21` would end up as `RST` and `NSS`. USB CDC is
enough for logging, but a serial console is cheaper to keep than to get
back.

**A's price is that USB-C ends up above the `+5V` and `3.3V` pads.** During
assembly that does not matter, because the wires are soldered before the C3
— but repairing them requires removing the C3. Do them carefully in one go.

### Nothing matches the silkscreen

The C3's silkscreen says `GPIO5=MISO`, `GPIO6=MOSI`, `GPIO7=SS`. Here they
are `RST`, `NSS` and `MOSI`. `GPIO4=SCK` used to be the one match — and then
`MISO` and `SCK` were soldered the other way round, so now `GPIO4` carries
`MISO` and `GPIO3` carries `SCK`. Not one of the nine agrees with the
printing.

**That swap was absorbed in software, not with an iron.** On the C3 SPI goes
through the GPIO matrix and ESPHome takes the pins from the configuration,
so either pin serves either signal. Changing two lines was cheaper and safer
than desoldering two wires beside a mounted C3 — and it is exactly why the
pin choice was free in the first place.

That is functionally irrelevant — the C3 routes SPI through the GPIO matrix
and ESPHome takes the pins from the configuration — but **write the map on
the side of the board with a marker.** In three months' time the silkscreen
will be lying about eight pins out of nine.

Four points that easily go wrong:

- **Both supplies.** The transmitter side takes 5 V and peaks at hundreds of
  milliamps in an RF burst; the logic is 3.3 V. 100 µF next to the module —
  and **check that the SuperMini has a 5V pin**, not all clones do.
- **BUSY is mandatory.** The PN5180 is not an ordinary SPI slave: after
  every command one has to wait for BUSY to fall. Without it a read returns
  rubbish rather than an error — again a fault that does not look like one.
- **The whole module goes against the meter, and the C3 beside it.** The
  board that arrived is single-piece, so the antenna cannot be placed apart
  from the logic. SPI is a fast bus and does not tolerate long wires, so the
  C3 has to be within 10–20 cm — i.e. it ends up at the meter too. That is
  not a problem in this room, but it removes the flexibility a two-part
  model would have given.
- **The read distance is shorter than with a two-part module.** The
  integrated coil is smaller than a separate credit-card-sized antenna
  board, so aligning it to the meter's own coil is finer work. Allow time
  for it the first time.
- **Check the component's platform support before considering a D1 mini.**
  On an ESP8266 three safe pins remain after SPI, which is just barely
  enough — but `esphome_qalcosonicnfc`'s ESP8266 support is unverified and
  should not be assumed.

## NFC is also an alternative route for the whole project

[esphome_qalcosonicnfc](https://github.com/dbmaxpayne/esphome_qalcosonicnfc)
reads the W1 over NFC with a PN5180 module and brings consumption, flow,
temperatures, battery level and error flags into ESPHome. **It needs neither
an AES key nor a transmission window** — so it defeats both of this
project's obstacles at once.

The price is a new module and the fact that the receiver has to go next to
the meter, which overturns this file's own argument that wM-Bus lets you
choose the location freely. It is therefore a different project rather than
a fix to this one, but it exists if
the key never arrives.

---

# The actual ESPHome configuration

> **This block is wrong in two ways and is kept as a warning.** It is
> `version_4`'s schema, and its `type: axioma` does not exist as a driver at
> all — the right one is `q400`. The field names `water_m3` and `flow_m3h`
> are from the same invented-sounding family and have not been seen in any
> output.
>
> The form that runs is commented out in
> [`axioma.effection.yaml`](axioma.effection.yaml) and waits for the Meter
> ID and the key.

```yaml
sensor:
  - platform: wmbus
    meter_id: 12345678
    type: axioma

    water_m3:
      name: "Water meter"

    flow_m3h:
      name: "Flow"

    temperature_c:
      name: "Water temperature"
```

---

# GitHub projects

## The ESPHome Wireless M-Bus component

https://github.com/SzczepanLeon/esphome-components

### The versions are two generations, and this project mixed them up

Checked from the source on 6.9.2026. Two incompatible schemas are alive at
the same time, and the branch name does not say which is which:

| | Latest | Schema |
|---|---|---|
| `version_4` | 4.1.4, February 2025 | one `wmbus:` block, `gdo0_pin` + `gdo2_pin`, `sensor: - platform: wmbus` |
| **5.x** | **5.1.6, August 2025** | `spi:` + `wmbus_radio:` + `wmbus_meter:`, `irq_pin`, sensors on their own platform |

5.0.0's release note is `Full refactor/rewrite by Kuba`, which explains why
nothing carries over as it stands.

**The YAML was pinned to `@version_4` and wrote 5.x's schema.** It would not
have built: `wmbus_radio` does not exist in the four series. The error was
not in the choice of schema but in pinning a version without reading what
belongs to it — and the file's own comment praised the pinning on the same
line.

**The release tag `@5.1.6` was chosen as the fix, and that was wrong too.**
Validation rejected it immediately:

```
Unknown value 'CC1101', valid options are 'SX1276'.
'reset_pin' is a required option for [wmbus_radio].
[frequency] is an invalid option for [wmbus_radio].
```

**The five series does not know the CC1101.** The rewrite started from the
SX1276, and CC1101 came back only afterwards — into the main branch, which
has never been released. So no release exists with both CC1101 and the
current schema:

| | CC1101 | Current schema |
|---|---|---|
| `version_4` 4.1.4, 2/2025 | yes | no |
| `5.1.6`, 8/2025 | **no** | yes |
| `main` | yes | yes |

**The pin is therefore a commit hash**,
`7eae51c8fcefe854623b029b27bbe42e11c103ea`, the tip of main on 20.8.2026. It
is the only form that gives both: a branch moves, a tag has no CC1101, a
commit cannot change. The trade is that the code is unreleased — a conscious
choice, and the alternative would be `version_4`'s 19-month-old release with
the old schema.

`refresh: never` belongs with this: a fixed commit has nothing to update.

### Three rounds, and the lesson is source criticism

This was only settled on the third attempt, and every round fell over the
same thing: **the README was trusted as a source.**

| | Believed | Reality |
|---|---|---|
| 1 | `@version_4` + the new schema | different generations, `wmbus_radio` is not in the four series |
| 2 | `components: [wmbus_radio, wmbus_meter]` | `wmbus_common` is a dependency that is not mentioned |
| 3 | `@5.1.6` knows CC1101 because the README says so | the README is main's, the tag is not |

The third is the nastiest: main's README describes main's code, and it was
read as evidence about a tag. **Documentation always describes the branch it
is in.**

The answer came from `wmbus_radio/__init__.py`: radio types are discovered
from the `transceiver_*.cpp` files, `reset_pin` is optional and `frequency`
belongs to the CC1101. The source said in a second what three readings of
the README did not.

The same pattern as stiebel's `0x8000` sentinels and the `VD` abbreviation:
**a table is a hypothesis, the device's own utterance is evidence.**

### Bare-board boot log, 6.9.2026

Flashed without the CC1101 on purpose. This is a baseline that cannot be
recovered later, and it produced one unexpected result.

```
[C][wmbus.transceiver:157]: Transceiver: CC1101
[C][wmbus.transceiver:131]:   IRQ Pin: GPIO4
[C][wmbus.transceiver:163]:   Frequency: 868.950 MHz
[C][wmbus_common:013]: wM-Bus Component v5.1.7-1.19.0-fe1b1e0:
[C][wmbus_common:015]:   Loaded drivers:
```

**Nothing says the radio is not attached.** The component prints its
configuration at boot regardless of whether the chip answers over SPI, and
no error is produced.

This differs from stiebel, where a missing MCP2515 produces the line
`canbus is marked FAILED: unspecified` and a wiring fault is recognised
before the bus is touched. The configuration dump therefore distinguishes
nothing.

**But this used to say that the correctness of the wiring cannot be
established from the log, and that is wrong.** The check exists, hidden two
layers down:

```
[VV][CC1101]: part: 00, version: XX
```

It is printed under the tag `CC1101` **at VERY_VERBOSE level during setup**,
and the `version` register is the one piece of end-to-end evidence about
SPI: **the value must be `04` or `14`.** The part number cannot be trusted,
because the driver's own check fails only if it is something other than zero
— and a dead bus reads zero. `Invalid part number` therefore never comes
from wrong wiring.

Two reasons it has gone unseen:

- **The level is DEBUG**, and the line is at VV. VV can be raised and the
  SPI flood silenced per tag in the `logs:` block — an earlier comment
  rejected VV because of the flood and did not try the filter. The YAML has
  instructions for it, but the level is deliberately DEBUG: VV costs a
  megabyte of log per hour and CPU load, and gives nothing in return without
  a serial port.
- **The API log stream does not see setup.** `esphome logs` attaches only
  once the device is on the network, so the radio's setup,
  `Receiver task created` and any panic backtrace have already passed. These
  lines are visible only **from the serial port.**

The consequence for troubleshooting: if no frames arrive, **the log
separates the causes only when it is read from the serial port at VV
level.** Without that, wrong wiring, the wrong frequency, a silent meter and
a receiver that does not assemble frames all look the same in the log — like
zero.

Comparing the boot log after wiring against this does say one thing, though:
**if new lines appear with the radio attached, the component is asking the
chip something.** If the log is identical, it is not asking — and then the
reasoning above holds as it stands.

`Loaded drivers:` is empty because there is no meter block. That means the
58.3 % flash figure is **without drivers**.

The version reports as **`v5.1.7`**, so the pinned commit is one release
newer than `5.1.6`. That puts a number on what "unreleased code" means here.

Wi-Fi on the desk **−56 dBm**, network `IoT`, `axioma.local` /
192.168.1.119. That is a good reading, but it was measured on the desk — the
reading at the installation site is a different matter and it is the one
that decides.

A side note requiring no action: ESPHome suggests `sram1_as_iram: true`
(+40 kB of IRAM). IRAM is at 60.6 %, so there is room — noted in case it
ever runs out.

### Validated

```
podman exec esphome esphome config /config/axioma.effection.yaml
INFO Configuration is valid!
```

ESPHome 2026.8.2. The output confirms `radio_type: CC1101`,
`frequency: 868950000.0` and `type: esp-idf` — **the framework reservation
held open in this file is unnecessary**, ESPHome picks esp-idf (5.5.5) by
default.

The `GPIO5 is a strapping PIN` warning appears on every run and needs no
action. It is exactly the pin argued safe above.

**This does not mean the radio works.** Validation means ESPHome agrees to
build; the same evidential weight overturned two assumptions in a row in
stiebel. No hardware was connected.

### The driver is `q400`

There is no driver by the meter manufacturer's name. The Qalcosonic W1
auto-detects poorly, but `q400` reads it; the component offers the drivers
straight from wmbusmeters.

The published `q400` output shows the fields: `total_m3`,
`consumption_at_set_date_m3`, `meter_datetime`, `set_datetime`, `status` and
`rssi_dbm`. **Temperature is not in that list**, even though the W1 measures
one and even though this file has promised a `Water temperature` entity. It
is now commented out twice over and waits for the first decoded telegram —
which is the same rule as with the Meter ID: **the device's own utterance
beats the table.**

### Platform support

**The ESP8266 is not supported**, and the build says why that is not an
arbitrary restriction. The finished image is **1,069,167 bytes** — over a
megabyte, and that is a *listening* configuration with no meter sensors at
all:

```
RAM:   [===       ]  27.3% (used 49260 bytes from 180736 bytes)
Flash: [======    ]  58.3% (used 1069167 bytes from 1835008 bytes)
```

The D1 mini's application partition with OTA is about a megabyte, so this
simply would not fit. The question considered in this repo in terms of
memory and pins is therefore settled by size, and settled clearly.

**A comparison with the repo's others is in order, because this is clearly
the heaviest:**

| | Flash | RAM |
|---|---|---|
| stiebel, stage 1 | 45.2 % | 40.0 % |
| aidon | 46.8 % | 53.3 % |
| **axioma** | **58.3 %** | **27.3 %** |

The difference comes from wmbusmeters' driver code. RAM is the roomiest in
the whole repo, because the ESP32 has more of it — memory will not become a
problem, flash could. About 765 kB remain, and the meter block will add the
`q400` driver to that. It fits, but **if compiling all the drivers in ever
becomes tempting, this is the figure to look at.**

**The ESP32-C3 is explicitly tested** — main's README mentions
`ESP32-C3 Super Mini`. That settles another question that was open in this
repo: if the board ever changes to a C3, the component is not an obstacle.

**The framework choice is unverified.** The examples use `esp-idf` and this
has not been tried with Arduino. If the build fails on something other than
the schema, that is the first thing worth changing.

---

# Sources

Linked rather than copied, per the repo's convention.

- [StudioPieters — CC1101 868MHz SPI RF Module, Complete Guide](https://www.studiopieters.nl/cc1101-868mhz-spi-rf-module-complete-guide/)
  — a drawing of this exact module with pin numbers, and an ESP32 wiring
  table matching this project's own pin for pin
- [Cirkit Designer — CC1101 Module](https://docs.cirkitdesigner.com/component/c132ba5f-b3e5-4906-a71e-12913dd93300/cc1101-module)
  — a generic 10-pin description. **Does not apply to this board**, and it
  is here as an example of why a source has to be checked against the
  photograph
- [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components)
  — the ESPHome component used
- [wmbusmeters](https://github.com/wmbusmeters/wmbusmeters) — the drivers,
  of which `q400` reads the Qalcosonic W1
- [dbmaxpayne/esphome_qalcosonicnfc](https://github.com/dbmaxpayne/esphome_qalcosonicnfc)
  — the NFC component, pinned to commit `bed6773`

# Useful search terms

```
ESP32 CC1101 ESPHome wmbus
ESP32 CC1101 wiring
Wireless M-Bus ESPHome
Axioma Qalcosonic W1 Home Assistant
SzczepanLeon esphome-components
```

---

# Troubleshooting

## No data

Check:

- the antenna is attached
- it is an 868 MHz antenna
- the SPI wiring
- the 3.3 V supply
- the GPIO assignments

---

## Boot loop

Usually:

- GDO0 on the wrong pin
- CS on the wrong pin

---

## Poor reception

- the antenna too close to metal
- a long distance to the meter
- a poor antenna

---

# Next steps

**NFC is the primary route now**, because it depends on neither of the radio
side's obstacles. The radio work resumes only if NFC says wM-Bus is on.

1. **Transfer the wiring to the C3 that passed the pin test**, with `RST`
   and `NSS` back on `GPIO5` and `GPIO6`
2. Flash [`axioma-nfc.yaml`](axioma-nfc.yaml) and look for
   `[D][PN5180:185]: Register value=` — the first proof that SPI answers end
   to end
3. If it still does not answer, the module is the only suspect left
4. **Locate the meter's coil by looking**, fix the board loosely, read once
5. **Measure the duration of one read** and derive the polling interval from
   it with a factor of 2–3
6. **Read the radio state, mode and schedule masks from the meter** — they
   answer what the radio node has not answered in days
7. **Ask the water utility** for the radio state, the **mode** and the
   AES-128 key. Start this in parallel immediately, because it takes
   calendar time
8. Decode the first telegram and confirm the Meter ID and `q400`'s field
   names from it, not from a table
9. Add the meter to Home Assistant

The radio side's own remaining steps, if the meter turns out to transmit
after all:

- **Listen on 868.95 MHz on a weekday between 06:00 and 18:00.** Inside the
  default schedule, because both earlier measurements fell outside it or on
  the wrong frequency.
- **Verify SPI from the serial port at VV level.** Look for
  `[VV][CC1101]: part: 00, version: XX` and require `version` = `04` or
  `14`. The same run shows the setup lines the API log stream does not.
- **Lower the FIFO threshold in a local working copy:** `FIFOTHR` to `0x00`.
  This tests hypothesis 3's leading suspicion and requires nothing from
  anyone.

---

# Note

The Axioma Qalcosonic W1 normally transmits about every **16 seconds**, so
the first telegram may take a moment.

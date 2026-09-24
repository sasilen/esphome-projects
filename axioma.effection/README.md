# Axioma Effectio (Qalcosonic W1) → Home Assistant

> **Overview.** Technical detail and rationale: [`CLAUDE.md`](CLAUDE.md).

Reading a water meter wirelessly into Home Assistant with an ESP32 and a
CC1101 radio. The meter transmits a Wireless M-Bus telegram on 868.95 MHz
roughly every 16 seconds; the ESP32 receives it and forwards it over
ESPHome's native API. No MQTT.

**Status: the meter is read over NFC. Wi-Fi on that node is unsolved.**

The NFC route works end to end. On day 2 the whole chain ran: inventory,
M-Bus checksum, and a full readout — 255.547 m³, water 15.1 °C, external
18.0 °C, battery 91 %, error flags all zero, 847 days of operating time.

**One read takes 1027 ms**, which settles the polling interval at two
hours: 12 reads a day, about 31 % of the meter's communication credit — a
threefold margin against a budget figure that is itself an assumption.

Two things the repo had guessed wrong came out of it: **the Meter ID is not
the nameplate serial**, and the alignment to the meter's coil was found by
hand in minutes, because a failed inventory costs no credit.

**The radio route produced nothing.** About 36 hours of listening on
868.95 MHz, inside and outside the schedule window, gave **zero frames**.
The receiver is demonstrably fine — noise packets come through. The probable
reason is that the meter is on LoRaWAN metering: in the W1, LoRaWAN and
wM-Bus are separate flags, and a utility reading over LoRaWAN has no reason
to keep wM-Bus on. LoRaWAN is not an alternative local route, because its
keys live on the network server.

**What is open is Wi-Fi on the NFC node.** It associates occasionally and
mostly does not, on two different boards, at every signal level, in every
location, on every supply. Ten explanations were proposed and all were
retracted. **It does not block reading the meter** — the node reads over the
serial port with no network at all. The full record and what has been
excluded by measurement are in [`CLAUDE.md`](CLAUDE.md) under
"OPEN PROBLEM".

Along the way the first ESP32-C3 turned out to have **two dead GPIO pads**,
which cost an evening because continuity measured fine and only a driven pin
revealed it. The build moved to a replacement board that passed the pin
test — see [`pintesti.yaml`](pintesti.yaml).

The radio configuration is deliberately **a listener and nothing more**. It
cannot read the meter's values and does not try — it verifies the radio, the
wiring, the frequency and the signal. The sensor block sits commented out in
the file, waiting for two things: the Meter ID from the log and the AES key
from the water utility.

**Listen on a weekday between 06:00 and 18:00.** The meter's default
schedule is Mon–Fri 06:00–18:00, and outside it the radio is silent
altogether. Silence measured at night or at the weekend says nothing about
the hardware.

## The meter

| Property | Value |
|---|---|
| Manufacturer | Axioma |
| Model | Effectio / Qalcosonic W1 |
| Type | LT-1621-MI001-034 |
| SN | 12345678 — placeholder, the real one is on the nameplate |
| SW | 1.03 |
| Year | 2024 |

The Meter ID is probably the serial number `12345678`, but it is confirmed
from a received telegram — do not assume it in advance.

## Architecture

```
Axioma Water Meter
        │  Wireless M-Bus (868.95 MHz, T1)
        ▼
    CC1101 Radio
        │  SPI
        ▼
      ESP32
        │  ESPHome native API
        ▼
 Home Assistant
```

## Hardware

Everything is in stock, ordered for this project:

- **ESP32 DevKit, 30 pins** — the same board as
  [`../pegasos.enervent/esp32-devkit.jpg`](../pegasos.enervent/esp32-devkit.jpg).
  PCB antenna, USB-C, CH340C bridge. There are two of these on the shelf;
  pegasos takes the other
- **CC1101 868 MHz**, Huerous — [photo](cc1101-module.jpg), 26 MHz crystal.
  The antenna pigtail came with it
- **868 MHz omni antenna with SMA connector, 2 pcs**, QWORK, foldable

**Only one antenna is needed: 868 MHz for the CC1101.** The DevKit's Wi-Fi
is in the module's PCB antenna and needs no part. No external antenna is
required, because **wM-Bus is radio** — you choose where the receiver goes,
and you choose somewhere Wi-Fi reaches.

**The ESP8266 will not do, and the reason is size.** The built image is
1,069,167 bytes and the D1 mini's application partition with OTA is about a
megabyte — not a borderline case. The comparison with the repo's other
projects is in [`CLAUDE.md`](CLAUDE.md).

## Wiring

Drawn out: [`wiring.svg`](wiring.svg).

**The module has no pin markings on either side.** Turn the board so the
**crystal is up** and the text `CC11010 868MHz Module` reads vertically down
the left edge — then the eight holes are on the right and the order from top
to bottom is this:

| # | CC1101 | ESP32 | On the board | |
|---|---|---|---|---|
| 1 | CSN | GPIO5 | `D5` | strapping, but it wants HIGH and CS idles HIGH |
| 2 | GDO0 | GPIO4 | `D4` | `irq_pin` |
| 3 | GDO2 | — | — | **leave unconnected** |
| 4 | MISO | GPIO19 | `D19` | |
| 5 | SCK | GPIO18 | `D18` | |
| 6 | MOSI | GPIO23 | `D23` | |
| 7 | GND | GND | `GND` | |
| 8 | VCC | 3.3V | `3V3` | **not 5V and not VIN** |

**On the DevKit the `D` number is the GPIO number** — `D18` is GPIO18. The
same does not hold on a Wemos: there `D5` is GPIO14. All seven wires go to
the DevKit's upper row; the lower row needs no attention.

On the left edge, **GND — ANT — GND**; the middle one is the antenna.

**The hole pitch is 2.0 mm, not 2.54 mm** — Dupont jumpers do not fit.
Solder thin wire directly.

**Measure VCC and GND before applying power.** Only those two can destroy
the chip, and they can be identified without any table: between them the
resistance reading climbs slowly as the bypass capacitors charge. If the
pair is found at the end of the row the table promises, the whole
orientation is proven with one measurement.

**The CC1101 runs on 3.3 V only — never use 5 V.**

**GDO2 stays unconnected.** The current component needs one interrupt line
and that is GDO0. The old table routed GDO2 to GPIO2, which is a **strapping
pin** — an output driving it prevents startup, and this project's own
troubleshooting table records exactly that as a cause of boot loops.

Pin orders vary between modules; check your own module's silkscreen rather
than trusting a generic diagram.

## ESPHome

Component: [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components).

**Two incompatible generations of the component are alive at the same
time.** `version_4` (latest 4.1.4, 2/2025) uses a single `wmbus:` block with
separate `gdo0`/`gdo2` pins; **5.x** (latest 5.1.6, 8/2025) is a full
rewrite and uses ESPHome's own `spi:` component, a `wmbus_radio:` block with
a single `irq_pin`, and a separate `wmbus_meter:` block.

**And neither release will do here.** `5.1.6` is the newest, but the five
series' rewrite started from the SX1276 and does not know the CC1101 at all;
CC1101 came back only into the main branch, which has never been released.
No release exists that has both CC1101 and the current schema.

The source is therefore pinned to a **commit hash**, not to a branch or a
tag — that is the only form that gives both. The trade is that the code is
unreleased.

The driver is **`q400`**, not the meter manufacturer's name. Rationale, the
version table and the state of the fields are in [`CLAUDE.md`](CLAUDE.md).

The configuration is **validated** with ESPHome 2026.8.2
(`Configuration is valid!`). That means ESPHome agrees to build it — not
that the radio works.

```sh
podman exec esphome esphome config /config/axioma.effection.yaml
```

When the radio works, a line like this appears in the log:

```
Received T1 A frame from 12345678 RSSI -70
```

That one line says four things at once: the radio works, the wiring is
right, the frequency is right, and the meter is audible to the receiver.

## Flashing the radio node

**Flash before you connect anything.** The reason is not habit but that
validation is not a build: `esphome config` checked the schema, but the
source is an unreleased commit and not a line of C++ has been compiled. And
a bare board gives a baseline — once the log is known without the radio, the
first silence with the radio is wiring or reception rather than the sum of
three unknowns.

The same distinction is recorded in
[stiebel](../stiebel.eltron/CLAUDE.md) as a chapter of its own: an SPI fault
and a bus fault look identical from outside, i.e. nothing happens.

**1. Validate.** No hardware, seconds:

```sh
podman cp axioma.effection/axioma.effection.yaml esphome:/config/
podman exec esphome esphome config /config/axioma.effection.yaml
```

`INFO Configuration is valid!` means the schema is acceptable. The
`GPIO5 is a strapping PIN` warning appears every time and needs no action —
see Wiring.

**2. Build and write it to the board.** The container is on the server and
the board most likely goes to a laptop, so the same route as in aidon:
**Install → Manual download** in the ESPHome web UI, and the `.bin`
separately to the board. The first build takes minutes because it fetches
the toolchain.

The board is **USB-C** with a **CH340C** bridge, so the machine needs a
CH34x driver — not CP210x. If the port does not appear, `dmesg` says which
device showed up at plug-in.

```sh
sudo esptool --port /dev/ttyUSB0 --baud 115200 write_flash 0x0 firmware.bin
```

Use the `factory` file, not the `-ota.bin` one. `Permission denied` is
solved by `sudo usermod -a -G dialout $USER` and logging out.

**3. Look at the boot log bare.** No CC1101, no antenna. Note down what
`wmbus_radio` says when there is no radio — that line is a baseline you
cannot get back later.

Wi-Fi connects and the API comes up. `Wi-Fi` starts updating every minute.

**4. Measure the signal where the board is actually going.** Battery pack,
board in place, hatch closed if there is one. `Wi-Fi` tells the truth. This
is cheap now and expensive later — in aidon it was measured too late and is
still at the top of that project's open-issues list.

**5. Unplug USB. Wire it up.** Seven wires, GDO2 left off, the 868 MHz
antenna on the CC1101 **before** power. See [`wiring.svg`](wiring.svg).

**6. Power back on and wait.** The transmission interval is ~16 s, but do
not read silence as a fault before you have waited a couple of minutes.

After that all updates go over OTA and the board never has to come out
again.

## Obstacle 1: the meter does not transmit wM-Bus

The receiving side is proven as far as it can be without a frame: SPI and
the interrupt work, the frequency and mode are right, and lowering the FIFO
threshold from 32 bytes to four changed nothing. What is left is the meter,
and LoRaWAN explains it without anything being broken.

**The solution is a request, not code:** is `wMBus T1` on, and can it be
switched on. It is the utility's device and a refusal is possible.

NFC would tell the radio state directly, bypassing the utility, but **the
phone route is closed:** the meter's NFC is ISO 15693, which Android routes
only to a permitted application — and none is available. A bare tap is
silent even with the tag in the field.

## The bypass: PN5180 defeats both obstacles

A five-euro NFC module reads the meter directly with no AES key, no
transmission window, and regardless of which radio the utility uses. The
price is that the receiver has to go next to the meter — so Wi-Fi has to
reach where the meter is. See [`CLAUDE.md`](CLAUDE.md).

The module has arrived: **PN5180-NFC R1.1, 70 × 39 mm**, single-board. It
gets a node of its own on an **ESP32-C3 SuperMini** — the radio node is left
alone, because an NFC read is what answers the remaining question about
wM-Bus. Configuration is [`axioma-nfc.yaml`](axioma-nfc.yaml), wiring
[`nfc-c3-mount.svg`](nfc-c3-mount.svg).

## Obstacle 2: the AES-128 key

The Qalcosonic W1 normally uses AES-128 encryption. The key is **not** on
the display, the nameplate or in the serial number — it has to be requested
from the water utility, the building manager, the developer or the meter's
supplier. Without it only encrypted telegrams are visible.

Put this in motion straight away, because it takes calendar time. **Ask for
the radio state and the mode at the same time** — the mode decides whether
the hardware choice is right, and it is not worth finding out in two
rounds.

## Flashing the NFC node — before soldering

**Flash the C3 first, bare.** That is not habit but order, and there are two
reasons:

- **`BOOT` and `RESET` are on the surface of the board**, and the header
  goes right beside them. On a bare board they can be pressed with a finger.
- **A faulty board is found before nine joints have been made on it.**
  There are six C3s on the shelf; swapping costs minutes now and an evening
  after soldering.

And a third reason is in what gets flashed: in stage 1 `axioma-nfc.yaml` is
**a bare skeleton with no SPI and no NFC component.** Wi-Fi, the API and OTA
are verified separately from whether the component's configuration is right
— two unknowns at once is one too many.

**1. Copy and validate.** The container's `/config` is flat and
`secrets.yaml` is already there, shared:

```sh
podman cp axioma.effection/axioma-nfc.yaml esphome:/config/
podman exec esphome esphome config /config/axioma-nfc.yaml
```

`INFO Configuration is valid!` before the USB cable comes out.

**2. Build and keep the `.bin`.** From the ESPHome web UI,
**Install → Manual download → Factory format**. The first build fetches the
C3 toolchain and takes minutes.

Use the `factory` file, not the `-ota.bin` one. The latter is only the
application partition and assumes the board already has a bootloader and a
partition table.

**Both `axioma-nfc.yaml` and `pintesti.yaml` use `name: axioma-nfc`**, so
they build into the same directory and produce an identically named file.
That is convenient in Home Assistant and a trap at the bench: grab the
`.bin` immediately after the build you meant, and if in doubt, grep the boot
log for `GPIO Switch` to see which one is actually on the board.

**3. Put the board into download mode.** Either works:

| | |
|---|---|
| Cable connected | hold `BOOT`, tap `RESET`, release `BOOT` |
| Cable disconnected | hold `BOOT` while plugging in USB, release `BOOT` |

**4. Write.** The C3 SuperMini has **native USB and no bridge chip** — no
CH340C as on the DevKit, and therefore no CH34x driver. The port is
`/dev/ttyACM0` rather than `/dev/ttyUSB0`:

```sh
sudo esptool --chip esp32c3 --port /dev/ttyACM0 write_flash 0x0 firmware.factory.bin
```

If the port does not appear, `dmesg` says what happened at plug-in.
`Permission denied` is solved by `sudo usermod -a -G dialout $USER` and
logging out.

**The number moves.** Native USB means the port device disappears and is
recreated at every reset and every flash, so it may be `ttyACM1` tomorrow.
`ls /dev/serial/by-id/` gives a name that does not move.

**5. Verify from the device, not from the command's exit status.** This is
the repo's own rule and it has been earned: `esphome run` has succeeded in
appearance while the OTA never even started.

```sh
podman exec esphome esphome logs /config/axioma-nfc.yaml
```

The expected result is three things: Wi-Fi connects, the API comes up, and
**`Uptime` starts running from zero.** `Uptime` is the only line that
distinguishes a reboot from a log client merely attaching — the
configuration banner repeats on every attach and proves nothing.

`hardware_uart: USB_SERIAL_JTAG` is in the YAML for exactly this. Without it
the serial port is silent and a working board looks dead.

**Give association a couple of minutes, and do not use the fallback AP as a
sign.** The first boot associated only on the sixth round, and it took about
two minutes. Before that the log repeats `Restarting adapter`, and **every
restart takes the fallback AP down and back up** — so the AP flickers rather
than staying in the network list. A missing `Axioma NFC fallback` does not
mean the board is not starting; it means just as well that it is currently
trying.

The serial port is therefore the only honest way to watch this phase, and it
is the same rule as everywhere else in this repo: **the API log stream
cannot show why a device is not on the network**, because it attaches only
once the device is.

**6. Measure the signal where the board is actually going.** Battery pack,
board next to the meter. The expectation is about **−70 dBm**, because the
1-Wire node in the same room reads that. This is cheap now and expensive
after soldering.

**6.5. Verify the pins before you solder.** Flash
[`pintesti.yaml`](pintesti.yaml) and measure seven pads against ground — all
of them must be **~3.3 V**.

It drives every pin the wiring uses high unconditionally, and one
unconnected pin is included as a control. Whichever does not rise is broken
— and swapping the board costs minutes at this stage.

**Measure the control first.** If `GPIO1` does not read 3.3 V the test is
invalid and the other readings mean nothing: wrong binary, wrong ground
point or wrong pad. Only once the control is up does a low reading on
another pin mean a broken pin.

**This would have saved an entire evening.** `GPIO5` and `GPIO6` turned out
to be broken only after nine joints had been made and the wiring measured
good three times over. The break was inside the C3 between the pad and the
die, so **a continuity measurement passed and told the wrong story:**
continuity proves a conductor exists, this test proves a signal gets
through.

And a pin does not reveal its fault until it is used. That board had been
flashed and had run Wi-Fi faultlessly with those two broken the whole time.

**7. Unplug USB and solder.** The order is forced, because there is no
getting a soldering iron under the C3 once it is in place: five enamelled
wires first, then the header, then the C3 on top. See
[`nfc-c3-mount.svg`](nfc-c3-mount.svg) and [`CLAUDE.md`](CLAUDE.md).

**Check `BUSY` first if something does not work.** When `GPIO8` and `GPIO9`
are pulled out of the header, `GPIO10` is left alone behind two empty
positions with no support from its neighbours. That is not a known fault but
the weakest point of the structure.

**Do not use `GPIO20` or `GPIO21` as substitutes.** They are free as far as
the logger is concerned — it uses USB — and they still hang the boot at
`Using HW SPI: SPI2_HOST`, with no `spi_device` line at all. Changing only
the pins away from them removed the symptom; nothing else was touched.

**And 100 µF next to the PN5180**, between `+5V` and `GND`. **This was
missing from the first version of these instructions**, and it is exactly
the part easiest to leave out: nine connections are listed by name and the
capacitor is not one of them.

The transmitter side peaks at hundreds of milliamps during an RF burst, and
the same supply drives the C3's radio. A dip at that moment **looks like a
network fault rather than a power fault** — `4-Way Handshake Timeout` and
`Handshake Failed` are its symptoms, not the symptoms of a weak signal.

**Measure before applying power.** Multimeter, three things in this order:

```
5V  ↔ GND      open          these three can destroy something
3V3 ↔ GND      open
5V  ↔ 3V3      open
```

On the C3's far row the order is `5V` `GND` `3V3` — **ground sits between
the supplies**, so both possible shorts are between adjacent pins.

Then two bridges that destroy nothing but prevent startup:

- **`GPIO3` ↔ `GPIO2`.** The far row reads `GPIO4` `GPIO3` `GPIO2` and the
  wires go to the upper two. `GPIO2` is a strapping pin, so a bridge ties
  `MISO` to it
- **The four removed positions open.** The C3's `GPIO8` `GPIO9` `GPIO20`
  `GPIO21` must not connect to JP1's `MISO` `SCK` `GND` `GPIO` pads

And only then the nine continuity measurements per the wiring table.

**Measure the neighbouring pairs too, not just each connection.** Continuity
proves a conductor exists; it does not prove the conductors are separate. A
bridge between `MOSI` and `MISO` passes every per-connection test and breaks
SPI completely.

**`GPIO8` and `GPIO9` are not pulled out merely because they are strapping
pins.** They would connect straight to the PN5180's `MISO` and `SCK` lines,
which are already wired to `GPIO3` and `GPIO4`. At boot `GPIO8` must be high
and `MISO` would drag it low — **the board would not start at all.** That is
also the symptom if a joint has bridged.

**The board still has stage 1's firmware, and that is a functional test.**
If the board comes up and joins the network after soldering, no strapping
pin is being held. But separate the two causes from the serial port, not
from the network:

| Serial port | Interpretation |
|---|---|
| Empty, or repeating text | **Soldering.** A strapping pin held, or a short |
| Boots, `Restarting adapter` repeats | **The same Wi-Fi problem as before soldering** — unrelated to the joints |

**8. Only then stage 2.** It is active in
[`axioma-nfc.yaml`](axioma-nfc.yaml) and goes over OTA. The USB-C connector
ends up above the `+5V` and `3.3V` pads, so the cable is no longer
convenient to attach.

The keys are **verified from the source** rather than from the README, and
three things were wrong in the first guess: the component's name is
`qalcosonicnfc` with no underscore, the pins carry the prefix `pn5180_`, and
**no separate `spi:` block is needed** — the component's `AUTO_LOAD`
includes it and it takes all six pins as its own options. The source is
pinned to a commit hash, as in the radio node.

And the polling interval is **three hours, not one.** The meter's
communication credit is about 20 min/month, i.e. 40 s/day, and an hourly
interval already exceeds the budget at two seconds per read. Rationale and
measurement instructions: [`CLAUDE.md`](CLAUDE.md).

## Troubleshooting

| Symptom | Check |
|---|---|
| No data | Antenna attached, 868 MHz antenna, SPI wiring, 3.3 V, GPIO assignments |
| Boot loop | GDO0 or CS on the wrong pin — or a wire on GPIO2 |
| Poor reception | Antenna too close to metal, distance, antenna quality |

The first telegram may take a moment — the interval is about 16 seconds
**inside the schedule window.**

## Next steps

**NFC is now the primary route**, because it depends on neither obstacle —
36 hours of listening produced zero frames, and there is no point continuing
the radio work until the meter's own configuration has been read.

1. **Transfer the wiring to the fresh C3** that passed the pin test, with
   `RST` and `NSS` back on `GPIO5` and `GPIO6`
2. Flash [`axioma-nfc.yaml`](axioma-nfc.yaml) and look for
   `[D][PN5180:185]: Register value=` — that line is the first proof that
   SPI answers end to end
3. If it still does not answer, the module is the only suspect left and a
   replacement is justified
4. **Locate the meter's coil by looking**, fix the board loosely, read once
5. **Measure the duration of one read** and derive the polling interval from
   it with a factor of 2–3
6. Read the radio state, mode and schedule masks from the meter — they
   answer what the radio node has not answered in days
7. Ask the water utility in parallel: is `wMBus T1` on, in which mode, and
   the AES-128 key. This takes calendar time, so start it immediately
8. Add the meter to Home Assistant

**The radio node stays up and is not dismantled** until NFC has said whether
wM-Bus is on at all. If it turns out to be switched on, what remains is
verifying SPI from the serial port (`[VV][CC1101]: part: 00, version: XX`,
where `version` is `04` or `14`) and decoding the first telegram.

Details: [`CLAUDE.md`](CLAUDE.md).

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
- RJ11 cable — **not in stock, the one thing this project is waiting for**

### Optional

- RJ11 breakout adapter (not required if you are willing to cut one end of an RJ11 cable)

### The board in stock

Three ESP32 boards are on the shelf: **two of this type** — photographed in
[`esp32-devkit.jpg`](esp32-devkit.jpg) — and one DevKitC WROOM-32U. Take one of
the pair. **The other is no longer spare**: it went to
[`../axioma.effection/`](../axioma.effection/), which had been holding the
WROOM-32U on an antenna argument that did not survive scrutiny. The WROOM-32U
went to [`../hirvirata/`](../hirvirata/) instead, where an external antenna
earns its keep — the enclosure is outdoors and a brushed motor sparks next to
it. All three boards are now allocated.

What the photo settles:

- **30-pin DevKit layout**, 15 pins per side. Every pin in the wiring table below
  is brought out on it.
- **USB-C**, not micro-USB, and the USB bridge is a **CH340C** — so it is the
  CH34x driver that has to be present on the flashing machine, not CP210x.
- On-board **AMS1117-3.3** regulator, and a `VIN` pin, so 5 V may be fed in
  directly instead of over USB.
- The module carries a **printed PCB antenna**, i.e. plain WROOM-32. That is the
  right board to take for this project: it needs no antenna part, and a
  ventilation unit sits indoors where a PCB antenna is enough.

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

## Why ESP32 instead of ESP8266?

Although an ESP8266 can technically communicate over Modbus, the ESP32 is the better choice because it offers:

- Multiple hardware UARTs
- Better ESPHome support
- Easier debugging while Modbus is running
- More reliable long-term serial communication
- Better expandability for future sensors or controls

ESP8266 is usable but requires disabling the serial logger and has fewer resources.

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

## RJ11 Notes

The Enervent uses an RJ11 connector rather than screw terminals.

An RJ11 breakout board is **not required** if:

- a normal RJ11 cable is used
- one end of the cable is cut
- the conductors are stripped and connected directly to the MAX485

A breakout adapter is only recommended because it makes identifying the correct pins easier.

## Important Warning

Do **not** assume the RJ11 pinout.

The connector may contain:

- RS-485 A/B
- Ground
- Supply voltage

The pinout should be verified before wiring.

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

The following information still needs to be determined:

1. RJ11 pinout
2. Modbus slave address
3. Enervent Modbus register map

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

1. Obtain or identify the RJ11 pinout.
2. Connect the MAX485 to the ESP32.
3. Flash ESPHome onto the ESP32.
4. Verify Modbus communication.
5. Identify the correct Modbus registers.
6. Add sensors, switches and controls in ESPHome.
7. Integrate with Home Assistant.

## Long-Term Goal

Create a completely local integration for the Enervent Pegasos Eco ECE that provides monitoring and control through Home Assistant without relying on any cloud service.

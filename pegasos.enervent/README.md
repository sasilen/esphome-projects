# Enervent Pegasos Eco ECE → Home Assistant

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

Local monitoring and coarse control of an Enervent Pegasos Eco ECE ventilation
unit from Home Assistant, over the **potential-free terminals the unit already
provides**. No cloud service, no MQTT — the ESPHome native API only.

**Status: planning, and the plan changed completely.** This project was built
for eighteen commits on the assumption that the unit speaks Modbus RTU over a
service port. **It does not.** The manufacturer's own ECC manual settles it, and
what replaces Modbus is a row of dry contacts. Reasoning in
[`CLAUDE.md`](CLAUDE.md), "The Modbus route is closed".

## Is this worth building?

**Not for the electricity saving.** That has to be said first, because it is the
reason people usually start.

The fans are EC motors drawing perhaps 50–150 W together at full speed. Running
one step lower saves tens of watts. The larger number is ventilation heat loss —
maybe 300–400 W through a Finnish winter even after 80 % heat recovery — and
halving the airflow while the house is empty might recover a third of that for
the hours it applies. Call it **€20–40 a year, optimistically**, and it is
bought by under-ventilating a house, which is a trade against indoor air quality
and moisture, not a free win.

**The electric afterheater is not reachable.** It is the one kW-class load in
the unit and it is governed by the board's own logic. No terminal exposes it.

So the value is elsewhere, and it is worth being honest about how much there is:

| What | Worth |
|---|---|
| **Fault output as a notification** | **The whole case.** The fault light is the only reason to look at the panel; a dry contact turns it into a message on your phone |
| Boost / away automation | Convenience. Real but small, and a physical button does most of it |
| Duct temperatures | Data. Heat recovery efficiency and defrost cycles become visible |
| Electricity saving | Negligible — see above |

**If the panel is only ever consulted for the fault light, the project is one
binary sensor.** That is an evening's work with parts already on the shelf, and
it converts "notice it next time I walk past" into "know within a minute". The
rest is optional and can be added later or never.

That is the honest scope. The phases below are ordered by that.

## Architecture

```
Enervent Pegasos Eco ECE
        │  potential-free terminals on the control board
        │  S1–S4 speeds · OVERP boost · fault output
        ▼
   ESP32 + relays, one input
        │  ESPHome native API over Wi-Fi
        ▼
 Home Assistant (Podman)
```

Nothing touches the unit's own bus, its 0–10 V fan drive, or its protection
logic. The manufacturer documents an external humidity hygrostat wired to
exactly these terminals to change speeds — the relay board does the same thing
the hygrostat does.

## The terminals

From the manual's own external-cabling table:

| Terminal | Function | Type |
|---|---|---|
| `S1` `S2` `S3` `S4` | **fan speeds 1–4** | potential-free contact |
| `OVERP` | overpressure / fireplace boost | momentary, spring-return |
| `STOP` | ventilation emergency stop | potential-free contact |
| `ALARM` | external fault input (fire, frost) | potential-free contact |
| `LTOC` | cooling recovery | max 35 V |
| `NC` `COM` `NO` | **fault output** | potential-free, max 250 VAC / 1 A |

`NC/COM/NO` is the one that matters first. It is an output *from* the unit, so
it is read rather than driven.

## Hardware

**Required**

- ESP32 or ESP8266 — several on the shelf, and phase 1 needs one GPIO
- For phase 2: a relay board, one relay per contact to drive

**Freed by the change of plan**

- The **4P4C cable** is no longer needed. This project waited on it for two
  weeks and no longer waits on anything
- The five **JZK RS-485 modules** allocated here have no use in this project.
  They return to the shelf unallocated

**Do not wire anything to `TF CTRL` or `PF CTRL`.** Those are the board's own
0–10 V outputs *to* the EC fans, and there are trimmers by the same name for
setting airflow. Driving them means fighting the board's driver and bypassing
defrost and frost protection. See [`CLAUDE.md`](CLAUDE.md).

## Phases

**1. Read the fault output.** One GPIO with a pull-up against the `COM`/`NO`
pair, one `binary_sensor`, one Home Assistant notification. This is the phase
with the payoff, and nothing else depends on it.

**2. Drive the speeds.** Relays on `S1`–`S4` and `OVERP`. Away mode, night
setback, boost. Only worth doing if an automation is actually wanted — the unit
runs perfectly well without it.

**3. Measure the ducts.** DS18B20 in supply, extract, outdoor and exhaust.
Gives heat recovery efficiency and makes defrost visible. Pure data, no control.

The unit's own `T1`, `T2` and `T3` sensors are on quick connectors inside, but
they are the board's inputs and are better left alone; own sensors in the ducts
cost two euros and risk nothing.

## What this project used to be

Eighteen commits of Modbus RTU over a 4P4C "Freeway" service port: a pinout, a
baud rate, a register map, a probe configuration and a nine-step wiring
procedure. All of it was inherited from documentation for **EDA** automation,
and this unit has **ECC05** — the generation before.

The reasoning, the evidence that overturned it, and the register table that is
still correct for anyone arriving here with an EDA unit are kept in
[`CLAUDE.md`](CLAUDE.md). The superseded wiring drawing has been removed rather
than left to mislead; it is in the git history.

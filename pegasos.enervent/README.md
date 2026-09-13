# Enervent Pegasos Eco ECE → Home Assistant

> **Overview.** Technical details and reasoning: [`CLAUDE.md`](CLAUDE.md).

## Verdict: not worth building. 13.9.2026

The unit is an Enervent Pegasos eco ECE with ECC05 automation. It can be
monitored and coarsely controlled through the potential-free terminals on its
control board — that part is settled and documented. **The question is whether
it is worth doing, and the answer is no.**

Recorded rather than deleted, because the reasoning is the useful part and
because the conditions that would reopen it are worth stating.

## Why not

**There is no energy saving in it.** The fans are EC motors drawing perhaps
50–150 W together; a step down saves tens of watts. Reducing airflow while the
house is empty might be worth **€20–40 a year at best**, and it is bought by
under-ventilating a house, which trades against indoor air quality and moisture.
The one kW-class load is the electric afterheater, and **no terminal exposes
it** — the board governs it with its own logic.

**The panel is only ever consulted for the fault light.** So fan speed control
automates a behaviour that does not exist: nothing in this house changes
ventilation speed by hand, and an automation that replaces nothing saves
nothing.

**The fault light is the one thing with real value, and it is behind a
230/400 V enclosure.** A dry contact turning a wall LED into a phone
notification is a genuine improvement. It is also an electrician's visit for one
binary sensor, which is the wrong ratio on its own.

**Duct temperatures answer no question that is being asked.** Heat recovery
efficiency and defrost cycles would become visible. Nobody is currently asking
what they are, and a measurement with no decision attached to it is a hobby, not
a project.

**And the machine works.** It has ventilated this house for years without any of
this. Nothing in the building is worse because this project does not exist,
which is the test that matters.

## What would reopen it

Any one of these turns a "no" into a "yes", and none of them is far-fetched:

- **An electrician opens that enclosure for another reason.** The fault contact
  is then twenty marginal minutes rather than a visit of its own. The manifold
  override relay discussed for the heating system is exactly such a visit
- **The unit faults and it goes unnoticed** for long enough to matter. The
  notification acquires a value it does not have while nothing has gone wrong
- **Ventilation heat loss becomes a real question** in the heat pump work. It is
  a 300–400 W term in this house's winter heat balance, currently estimated
  rather than measured, and four duct sensors would settle it
- **Somebody starts wanting away or boost automation** — which would mean the
  behaviour exists and there is something to automate

The first is the likeliest, and it costs nothing to be ready for: the terminal
list is in [`CLAUDE.md`](CLAUDE.md) and the configuration is written.

## What is kept

- [`CLAUDE.md`](CLAUDE.md) — the terminal list, what the manual says, why the
  Modbus route was wrong, and the official EDA register map for anyone who
  arrives here with a newer unit
- [`pegasos.enervent.yaml`](pegasos.enervent.yaml) — phase 1, reading the fault
  contact. Written and unflashed. Correct but unneeded, so it stays rather than
  being deleted; if the verdict changes it is ready
- `secrets.yaml.example`, and the part photographs that other files link to

## The lesson that outlives the project

This project spent **eighteen commits building on a transferred assumption**:
Modbus RTU over a 4P4C service port, complete with a pinout, a baud rate, a
register map, a probe configuration and a nine-step wiring procedure. All of it
came from documentation for **EDA** automation. This unit has **ECC05**.

The model name said so the whole time — Enervent's own manual defines `ECE` as
*"ECC05-ohjauksella ja sähköisellä jälkilämmittimellä"*. The letter was in the
name on the type plate, and nobody read it as a specification.

Worse: **this repo already had the rule.** From
[`../stiebel.eltron/CLAUDE.md`](../stiebel.eltron/CLAUDE.md), written weeks
earlier about a connector pinout borrowed from a different heat pump series:

> **WPC is a different series. Do not transfer these numbers.**

The rule was written down and the same transfer was made anyway, because the
source was specific, confident, and about the right manufacturer. That is the
part worth carrying to the next project.

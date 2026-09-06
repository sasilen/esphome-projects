# Reading a heat pump that does not want to talk

*Part one of two. This half is about listening: getting onto the bus, decoding
what is on it, and finding out how much of what arrives is not data at all.
Part two is about writing to it.*

---

A Stiebel Eltron WPC 07 has a display. It shows perhaps a dozen numbers, one
screen at a time, and you have to be standing in the technical room to read any
of them. Behind that display is a CAN bus carrying **144 distinct data elements**
and about **95,000 frames a night**.

The gap between those two numbers is this project.

There is no official interface. Stiebel sells an internet gateway; this machine
does not have one, and buying one would mean a cloud account for data that is
already travelling on a twisted pair inside the casing. So: tap the bus, listen,
and work out what the traffic means.

## The one decision that shaped everything

The bus runs the **Elster protocol at 20 kbps** — a scheme shared across a
family of German heat pumps, documented mostly by hobbyists rather than by the
manufacturer.

An ESP8266 with an MCP2515 CAN controller can read it. But a CAN controller is
not a passive device by default: in normal mode it **acknowledges every frame it
receives** and transmits error frames when it sees something malformed. Put a
node with the wrong bit rate on a live heat pump bus and it does not quietly
fail — it actively disrupts the machine's own traffic.

So the node runs in **listen-only mode**. It never transmits, never
acknowledges, never signals an error. It is a tap, not a participant.

That decision protects the machine. It also, as it turned out, quietly changed
what arrives — but that comes later.

![Bus connection at X27](bus-connection.svg)

The tap point is `X27` on board A2, found in the manufacturer's own installation
manual. It is a spring terminal: solid conductor pushed in bare, or stranded
wire with a ferrule crimped on. **Never tinned** — solder cold-flows under
constant clamp pressure, the contact force bleeds away over months, and you are
left with an intermittent joint that is nearly impossible to find.

## Decoding

An Elster frame is seven bytes:

```
byte 0   receiver's high bits (>> 3) in the high nibble, command in the low
byte 1   receiver's low bits — nonzero only for a sub-addressed node
byte 2   element index, or 0xFA meaning "index is in bytes 3-4"
```

Six addresses are occupied on this machine: `0x100`, `0x180`, `0x301`, `0x480`,
`0x601`, `0x700`. Two independent polling loops run without anyone touching
anything — the manager asks the external device every five seconds, the panel
asks the boiler every ten.

The lesson that took longest to learn is in one line of the decoder:
**dispatch on sender *and* element, never element alone.** The same index means
different things on different nodes. Element `0xFDF4` from `0x700` is a return
temperature; the published element list's name for that index is something else
entirely, and the list is wrong for this machine.

That was established by correlation — 400 samples of `0xFDF4` against the
boiler's own `RUECKLAUFISTTEMP`, matching to a **median absolute difference of
0.0 K**. A published table later agreed. But the correlation came first, and
that order matters, because the same table is wrong about three other indices.

## The bug that cost more time than everything else

The MCP2515 has two receive buffers, and ESPHome polls them from the main loop.
On a busy bus a long loop stall — a WiFi reconnect, a burst of logging — fills
both buffers, sets the overflow latch, and the controller stops delivering
frames. Not an error, not a warning. Just silence.

The fix is a watchdog: count frames, and if the count has not moved for 20
seconds, restart the node.

Which introduced a second bug. ESPHome's safe mode counts boots, and its default
"boot is good" window is one minute. A node that runs 26 seconds and restarts
never resets that counter — after ten such restarts it boots into safe mode
**without the CAN component at all**, quietly, for the rest of the night. The
window had to come down to fifteen seconds, below the watchdog's own.

In eleven hours of ordinary running the watchdog fired **once** and recovered in
14 seconds. During a session of heavy logging it fired three times in four
minutes.

## The method that actually worked

Passive capture names very little. You get numbers with no labels, and
correlation only works where two things move together.

What works is the panel. On any screen the machine **asks the bus** for every
value it displays. Turn on logging of read requests, walk the menus, photograph
each screen, and then intersect: for each photograph, find the elements read
between it and the next, and look for one whose value matches a number on the
screen.

![The heating info screen](panel-info-heating.jpg)

Six minutes of this named **27 elements to the digit**. Eleven hours of passive
capture had named almost nothing.

A phone stamps the file name in UTC and the EXIF in local time. The EXIF is the
one to trust, and it lines up with the log to the second.

Ambiguity shows up as two elements holding the same number, and it is resolved
by finding a screen that shows one of them alone. Two elements both read −19.0;
the settings screen for the electric reheat asks for only one of them, which
names it and leaves the other by elimination.

![Running hours](panel-info-running-hours.jpg)

Five counters on one screen, all exact: 2215 hours of compressor on heating,
3530 on hot water, and 134 / 132 / 5922 on the electric element's two stages.

## What the numbers turned out to be

**A measured COP.** The machine keeps heat delivered and electricity consumed as
separate lifetime counters. For hot water: **18.972 MWh of heat from 7.526 MWh
of electricity — a coefficient of performance of 2.52**, over the machine's
whole life rather than a manufacturer's test cycle.

![Heat quantity](panel-info-heat-quantity.jpg)

That number came with a trap, and the trap is worth more than the number.

Every row on the consumption screen begins `VD` — *Verdichter*, the compressor.
There is no row for the electric element at all. Read carelessly, 7.526 MWh
looks like the machine's total hot-water electricity, and then the element's own
counters become arithmetically impossible: an element is COP 1, so 9.9 MWh of
heat needs 9.9 MWh of electricity, which is more than the machine drew in total.

This project wrote that impossibility down, called the element list wrong, and
concluded the element was disabled. **All of it was wrong, and the error was one
abbreviation.** `VD` is the compressor only. The element's electricity is not
counted on that screen. Read correctly, nothing is impossible and nothing needed
explaining away.

The lesson survives its own counterexample: checking a table against a
conservation law is the right instinct, and it did catch a real inconsistency —
but confirm what the denominator measures before declaring anything impossible.

**A fault list that is not faults.**

![The event list](panel-diag-event-list.jpg)

Twelve entries, all the same code: `8246`, roughly twice a day. The panel files
them under *fault list* because that is the only list it has. The code is the
**EVU block** — the utility load-control input.

And on this installation it is not the grid operator's doing. **Home Assistant
drives that input from the spot price**, to keep the compressor off during
expensive hours. The log agrees: the entries are not a fixed schedule but a
varying one — two on some days, one on others, and none at all on two days in
August. A contracted block would not skip two days. A price threshold would, on
a cheap one.

That makes the corresponding bus register worth an entity, but not for the
reason it first looks like. Home Assistant already knows when it *asked* for a
block. What it has never had is the machine's own report that the block arrived
and took effect. Those are different facts, and only the second one says the
wiring works.

**A flow temperature that was there all along.** The return temperature had been
readable from two independent nodes since the first capture. The flow from
none — until a panel screen named two elements, and both turned out to have
exact twins on the module that answers every five seconds whether or not anyone
is at the panel. The quantity was never missing. It was being logged
continuously under an index nothing had named.

## Four ways to receive something that is not data

This is the part that surprised me, and it is a direct consequence of listen-only
mode. The MCP2515 datasheet is explicit:

> Listen-Only mode provides a means for the MCP2515 to receive all messages
> (including messages with errors)… both valid and invalid messages will be
> received, regardless of filters and masks… **The error counters are reset and
> deactivated in this state.**

A frame corrupted on the wire is normally destroyed by an error flag from some
node on the bus. This node sends none — and no other node's flag can un-receive
a frame this one has already latched. So corruption arrives, intact-looking, and
has to be recognised in software. Four classes turned up:

**1. A corrupted sender identifier.** One frame in eleven hours arrived from
address `0x078`, which cannot exist: the addressing scheme puts the node in the
high nibble, so every real identifier is a multiple of `0x080`. Its payload was
a byte-perfect response that only one specific node could have sent. The payload
survived; the identifier did not.

**2. Sentinel values.** `0x8000`, `0x9000` and `0x8080` mean "not present". As
tenths they decode to −3276.8 °C. Three different nodes send them. Published as
a temperature, one lands in Home Assistant's history and stays there.

The panel says what they mean more precisely than the documentation does: on
every screen where a sentinel-answering element is displayed, the machine prints
`POIS` — *off*. It marks a function deliberately switched off, not a sensor that
is missing.

**3. An out-of-range value.** One element published 1584 once, against a lifetime
range of 0 and 51–58. Not a sentinel, so no guard caught it.

**4. A corrupted element index** — the subtlest one. An element answered 135
twice, in the millisecond after four consecutive reads of a *different* element
whose value is exactly 135 and whose index differs by one bit. Twenty-eight such
frames have now been seen, and **none of the indices they carry was ever
requested.** A response answers a request; an unrequested response is not
protocol traffic.

The flipped bits are not uniform. They cluster in the low bits of the two bytes
that carry the element index — fifteen of twenty-eight involve the same single
bit. That is a shape, not yet a diagnosis, and it points at the read path rather
than the wire.

**And the rate is a floor, not a measurement.** Only corruptions that land
*outside* the known element set are visible. A flipped bit that turns one real
index into another real index is delivered, published, and indistinguishable
from data.

Three of the four classes are guarded now. The fourth is deliberately not —
rejecting any element the manager did not just ask for is exactly the mechanism
by which a genuinely new element would be found.

## Being wrong, on the record

The technical documentation for this project is 2,300 lines, and a surprising
amount of it is retractions.

An early conclusion said two elements switch together and named the pair the
compressor. They do not, and it is not. A later one said a three-byte frame from
an unknown node must be real because the CAN checksum covers the identifier and
the length — true, but the checksum protects the wire, not the driver's buffer
handling. Another named a flow temperature from a single sample that happened to
match a plausible value; the same reasoning later pointed at a mangled index one
bit away, and the claim was withdrawn.

I made that last mistake twice. The second time I had already written the warning
against it, in the same file, a few hours earlier.

The pattern is consistent enough to be a method: **the wrong reasoning stays in
the file, and the retraction is written underneath it.** Not because errors are
charming, but because the reasoning is usually sound and the premise is usually
what failed — and you cannot see which is which if only the conclusion survives.

What emerged from all of it is a hierarchy of evidence, in increasing order of
strength:

- **A single sample that matches a plausible value.** Worthless. This is the
  error the corruption class produces.
- **Correlation over hundreds of samples.** Good. This proved the return
  temperature and two flow temperatures.
- **A screen photographed with the log running.** Better. This named 27 elements
  in six minutes.
- **Changing one value and watching the bus.** Best. When the legionella setting
  was toggled on the panel, the write appeared on the bus, named the element
  outright, and captured the exact frame that would command it.

That last one is not just the strongest evidence. It is also the shortest: ten
seconds, and no ambiguity to argue about afterwards.

## Where it stands

Fifty-one entities in Home Assistant. Temperatures, setpoints, running hours,
lifetime energy counters, the compressor state, the utility block. All of it
read-only, all of it from a node that has never transmitted a single frame.

Some of it updates every five seconds. Some of it only when somebody walks the
menus — and that is a property of the machine, not a defect of the reader. A
setpoint is still true between readings; a source temperature drawn as a flat
line for three days is a lie about the machine, so those entities carry no
statistics class and Home Assistant shows a number and a timestamp instead of a
graph.

Part two is about writing: taking an address on the bus, sending the frames that
have now been captured, and controlling the heating curve and the hot water
setpoint from the spot price. The frames are on record. The address is free. The
hardware question turned out to have a better answer than expected — and the
reason it did is a story about a validation command that costs nothing and had
been sitting unrun in the documentation for weeks.

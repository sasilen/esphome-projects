"""DS2406 — 1-Wire-kytkin, tässä luettuna ovikoskettimena.

Oma komponentti eikä `dallas_pio` suljetusta PR:stä #8091, kahdesta syystä.
Se ei käänny ESPHome 2026.9.0:lla, ja **sen DS2406-luku näyttää kirjoittavan**:
Channel Control Byte 1:ssä IM erottaa luvun kirjoituksesta, ja sen vakiossa
IM on 0 vaikka saman funktion kommentti sanoo IM=1. Perustelut ovat
CLAUDE.md:ssä.

Tämä toteuttaa vain luvun. Kirjoitusta ei ole tarkoituksella.
"""

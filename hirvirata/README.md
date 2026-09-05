# Hirvirata

Liikkuva maalitaulurata ilmakivääri- ja pienoisradalle. ESP8266 ohjaa 12 V
vaihdemoottoria H-siltaohjaimen kautta; hihna vetää vaunua kiskolla edestakaisin
eri nopeuksilla ja ohjelmilla. Ohjaus Home Assistantista ESPHomen natiivi-APIn yli.

**Tila: suunnitteluvaihe.** [`hirvirata.yaml`](hirvirata.yaml) on valmis luonnos,
mutta rautaa ei ole vielä koottu.

## Neljä mittausta ennen kuin tilaat mitään

Nämä ovat tekemättä ja voivat muuttaa komponenttivalintoja:

1. Moottorin akselin halkaisija — hihnapyörän reikä on kiinteä 6 mm
2. **Moottorin jumivirta** — jos > 2 A, L298N vaihtuu BTS7960:een
3. Moottorin kiinnitysreikien jako
4. U624ZZ-rullien uran mitat — valmistajakohtaisia, 4 mm tanko ei aina istu

## Rauta

| Osa | Tiedot |
|---|---|
| Ohjain | Wemos D1 mini (ESP8266), vaihtoehtoisesti mikä tahansa ESP32 |
| Moottoriajuri | ARCELI L298N -moduuli (5 kpl varastossa) |
| Moottori | 12 V vaihdemoottori, 200 rpm, ikkunanavaajatyyppi |
| Hihnapyörä | 41 × 16 × 6 mm, alumiini, yksi ura, kiinteä 6 mm reikä |
| Hihna | 5 mm PU-pyörähihna, päät hitsataan |
| Teholähde | Newding 12 V / 2 A pistokemuuntaja. **Rajatapaus** |
| ESP:n virta | LM2596 buck 12 V → 5,0 V |
| Vaunun rullat | U624ZZ, 4 × 13 × 7 mm, U-ura. **Eivät** kelpaa hihnapyöräksi |

ESP8266 ja ESP32 ovat molemmat kelvollisia — alusta vaikuttaa vain
`output:`-blokkiin ja pinneihin, `fan:`, `script:` ja `select:` ovat identtiset.
D1 minin ohjelmallinen PWM riittää 1 kHz:llä moottorinohjaukseen, mutta
**molemmilla PWM-lähdöillä täytyy olla sama taajuus** — ne jakavat saman ajastimen.

## Pinnijärjestys

Lyöty lukkoon.

| D1 mini | GPIO | Käyttö |
|---|---|---|
| D1 | 5 | PWM → L298N IN1 |
| D2 | 4 | PWM → L298N IN2 |
| D5 | 14 | Rajakytkin vasen (INPUT_PULLUP, inverted) |
| D6 | 12 | Rajakytkin oikea (INPUT_PULLUP, inverted) |

Vältä D3 (GPIO0), D4 (GPIO2) ja D8 (GPIO15) — käynnistysvastukset. D0 (GPIO16) ei
tue PWM:ää eikä sisäistä pullupia. ESP32-vaihtoehdon pinnit ovat
[`CLAUDE.md`](CLAUDE.md):ssä.

PWM menee **IN-tuloihin, ei ENA:han** — ENA/ENB-hyppyjohtimet jäävät paikoilleen.
3,3 V logiikkataso riittää L298N:n TTL-tuloille kun Vss = 5 V.

## Home Assistant -entiteetit

| Entiteetti | Tyyppi | Kuvaus |
|---|---|---|
| Vaunu | `fan` (hbridge) | Suora moottorinohjaus, nopeus 0–100, suunta FORWARD/REVERSE |
| Ohjelma | `select` | Seis / Tasainen / Satunnainen / Kiihtyvä |
| Perusnopeus | `number` | 20–100 %, oletus 60 |
| Ajoaika | `number` | 0,5–30 s, oletus 4 |
| Hätäseis | `button` | Ajaa `seis`-scriptin |
| Rajakytkin vasen / oikea | `binary_sensor` | Laukaisevat `seis`-scriptin |
| Vaunun nopeus | `sensor` | m/s, **laskennallinen arvio** — ei mittaus |

## Ajo-ohjelmat

Kaikki liike kulkee apuscriptin `aja(nopeus, eteen, kesto)` kautta, ja kutsuja
odottaa aina `script.wait: aja`.

- **Tasainen** — 20 edestakaista ajoa perusnopeudella, 3 s tauko päissä
- **Satunnainen** — satunnainen nopeus (35–100 %), suunta ja kesto (0,8–4,3 s)
- **Kiihtyvä** — kiihtyvä eteen 30→100 %, hidastuva takaisin 100→30 %

`aja` sisältää **pehmeän käynnistyksen** 50 % → 75 % → 100 % kolmessa 100 ms:n
askeleessa. Se ei ole kosmeettinen vaan pakollinen 2 A:n teholähteellä: ilman
sitä käynnistyspiikki notkauttaa 12 V:n ja buckin takana oleva ESP saattaa
bootata kesken ajon. Kokonaiskesto säilyy, koska rampin 300 ms vähennetään
loppuviiveestä.

### Uuden ohjelman lisääminen

1. Uusi script, `mode: restart`, `script.execute: aja` + `script.wait: aja` -pareista
2. Nimi `select`-komponentin `options`-listaan
3. Haara `set_action`in lambdaan
4. **`script.stop`-rivi `seis`-scriptiin** — tämä unohtuu helposti, ja ilman sitä
   rajakytkin ei pysäytä uutta ohjelmaa

## Turvallisuus

**Rajakytkimet molemmissa päissä ovat pakollisia, eivät valinnaisia.** Ilman niitä
vaunu ajaa päätyyn ja moottori jää jumiin täydellä virralla — se polttaa L298N:n
ja mahdollisesti moottorin. Kaikki muutokset scriptien pysäytyslogiikkaan pitää
tarkistaa tätä vasten.

Kytkinten yhteinen napa maahan ja **NC-kosketin** GPIO:hon, jolloin katkennut
johto laukaisee pysäytyksen sen sijaan että kytkin lakkaisi huomaamatta
toimimasta.

Sulake 12 V:n plussaan, 3 A. DC-jakkiliitin ruuviliittimillä teholähteen päähän.

## Tunnetut riskit

- **L298N on heikoin lenkki.** Jännitehäviö 1,5–2 V (moottori saa ~10 V),
  virrankesto ~2 A/kanava. Jos jumivirta on liian suuri: (a) rinnankytke kanavat,
  (b) vaihda BTS7960/IBT-2:een — sama YAML toimii muuttumattomana.
- **Älä syötä ESP:tä L298N:n 5 V -lähdöstä** — 78M05-lineaariregulaattori, ja
  WiFi-virtapiikit nollaavat ESP:n. Käytä LM2596:ta.
- **Teholähde 12 V / 2 A on rajatapaus.** Jos ESP bootaa uudelleen ajon aikana,
  syy on tässä — ei WiFissä. Pehmeä käynnistys + 2200 µF hoitavat sen.
- 2200 µF mahdollisimman lähelle L298N:ää ja 100 nF moottorin napojen väliin
  **moottorin päässä**. Kipinöinti häiritsee WiFiä.
- Pyöreä akseli ilman litteää kohtaa → hihnapyörä luistaa ensimmäisen
  suunnanvaihdon jälkeen. Viilaa lovi.
- Yhteinen GND ESP:n, L298N:n ja teholähteen välillä on pakollinen.

## Mekaniikka

**U624ZZ ei kelpaa kääntöpyöräksi** — 13 mm ulkohalkaisija on liian pieni 5 mm
PU-hihnalle (nyrkkisääntö ~10 × hihnan paksuus, eli vähintään 50 mm).
Kääntöpyöräksi tarvitaan toinen samanlainen 41 mm hihnapyörä.

Rullat ovat **vaunun ohjausrullia**: U-ura on tarkoitettu pyöreälle kiskolle,
4 mm terästangolle tai 3 mm kireälle teräsköydelle. Ei sovi
2020-alumiiniprofiiliin, joka vaatii V-uran. Akselina M4-pultti, kolme rullaa
vaunua kohti. 4 mm tanko notkuu 2 m matkalla — tue 3–4 kohdasta.

## Mitoitusrajoite

200 rpm ja 37 mm efektiivinen hihnapyörän halkaisija antavat **0,39 m/s**.
Virallisen juoksevan hirven nopeus on 4–5 m/s, mihin tarvittaisiin ~40 cm pyörä
(jolloin vääntö loppuu) tai selvästi nopeampi moottori. Tämä rata on mitoitettu
**1,5–2,5 m kulkuaukolle** pienoisrata- ja ilmakivääriharjoitteluun.

## Käyttöönotto

```sh
cp secrets.yaml.example secrets.yaml   # täytä omat arvot
esphome run hirvirata.yaml
```

Nopeussensorin kerroin `0.39` on laskennallinen. Kalibroi ajamalla vaunu tunnettu
matka täydellä teholla sekuntikellolla — ero paljastaa myös hihnan luiston.
`perusnopeus`-numberin `min_value: 20` on arvaus; vaihdemoottori ei todennäköisesti
lähde liikkeelle alle 25–30 %:lla.

Yksityiskohdat ja perustelut: [`CLAUDE.md`](CLAUDE.md).

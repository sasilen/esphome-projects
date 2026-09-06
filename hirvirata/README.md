# Hirvirata

> **Yleiskuva.** Tekniset tiedot ja perustelut: [`CLAUDE.md`](CLAUDE.md).

Liikkuva maalitaulurata ilmakivääri- ja pienoisradalle. ESP8266 ohjaa 12 V
vaihdemoottoria H-siltaohjaimen kautta; hihna vetää vaunua kiskolla edestakaisin
eri nopeuksilla ja ohjelmilla. Ohjaus Home Assistantista ESPHomen natiivi-APIn yli.

**Tila: suunnitteluvaihe.** [`hirvirata.yaml`](hirvirata.yaml) on valmis luonnos,
mutta rautaa ei ole vielä koottu.

## Neljä mittausta ennen kuin tilaat mitään

Nämä ovat tekemättä ja voivat muuttaa komponenttivalintoja:

1. ~~Moottorin akselin halkaisija~~ — **ratkaistu: 6 mm.** Hihnapyörä on kiinni
   moottorissa ja istuu. Sovitus on vahvempi todiste kuin mitta, ja se vapauttaa
   pyörävalinnat: 6 mm reikä on oikea, ja hyllyn 41 mm pyörä on oikea osa.
2. **Moottorin jumivirta** — jos > 2 A, L298N vaihtuu BTS7960:een
3. Moottorin kiinnitysreikien jako
4. ~~U624ZZ-rullien uran mitat~~ — **rauennut.** Vaunun rullat eivät enää kulje
   pyöreällä kiskolla vaan kumi- tai PU-rullina peltiä vasten, joten U-uran
   mitoilla ei ole merkitystä. Rullatuote on vielä valitsematta ja sen mukana
   akselikoko; ks. "Mekaniikka", joka kuvaa yhä vanhan ratkaisun.

## Rauta

| Osa | Tiedot |
|---|---|
| Ohjain | Wemos D1 mini (ESP8266), vaihtoehtoisesti mikä tahansa ESP32 |
| Moottoriajuri | ARCELI L298N -moduuli, 5 kpl |
| Moottori | 12 V vaihdemoottori, 200 rpm, ikkunanavaajatyyppi |
| Hihnapyörä | 41 × 16 × 6 mm, alumiini, yksi ura, kiinteä 6 mm reikä, **ura 3–5 mm hihnalle** |
| Hihna | 5 mm PU-pyörähihna, päät hitsataan. Koko tulee pyörän urasta, ei toisin päin |
| Teholähde | Newding 12 V / 2 A pistokemuuntaja. **Rajatapaus** |
| ESP:n virta | LM2596 buck 12 V → 5,0 V |
| Vaunun rullat | U624ZZ, 4 × 13 × 7 mm, U-ura. **Eivät** kelpaa hihnapyöräksi |

Taulukko kattaa vetolinjan, ei koko rataa. Muualla tässä dokumentissa
vaaditaan lisäksi nämä, eikä niiden varastotilannetta ole kirjattu:

| Osa | Tila | Miksi | Missä perusteltu |
|---|---|---|---|
| 2020 V-slot -profiili, 1,5–2,5 m | **puuttuu** | Vaunun kisko | Mekaniikka |
| Eksentriset välikkeet M5 | **puuttuu** | Ilman niitä pyöriä ei saa esikuormitettua | Mekaniikka |
| M5-pultit ja aluslevyt | **puuttuu** | Pyörien akselit | Mekaniikka |
| Sulake 3 A + inline-pidike | **puuttuu** | 12 V:n plussaan | Turvallisuus |
| DC-jakki ruuviliittimillä 5,5 × 2,1 mm | **puuttuu** | Teholähteen pää ilman johdon katkaisua | Turvallisuus |
| Rajakytkin ×2, NC-kosketin | valittu | **Pakollinen.** Ilman niitä moottori jää jumiin päätyyn | Turvallisuus |
| POM V-pyörä 625ZZ | valittu | Vaunun pyörät, 3–4 kpl | Mekaniikka |
| Kääntöpyörä 90 mm, laakeroitu | valittu | Taivutussääntö ≥ 50 mm | Mekaniikka |
| PU-pyörähihna 5 mm | valittu | Koko tulee vetopyörän urasta | Rauta |
| BTS7960 | valittu | Korvaa L298N:n; ks. jumivirtamittaus | Tunnetut riskit |
| 2200 µF / 100 nF | hyllyssä | Käynnistyspiikki ja kipinöinti | Tunnetut riskit |

Profiilin **rahti voi maksaa enemmän kuin profiili** — pitkä tavara on hankalaa
lähettää. Katso paikallista lähdettä tai kahta 1,25 m pätkää liitoskappaleella.

Kaksi riviä on poistunut ja se kannattaa tietää, jottei niitä osteta vahingossa:
**pyöreä kisko** (4 mm tanko tai 3 mm vaijeri) korvautui 2020-profiililla, ja
**toinen 41 mm hihnapyörä** kääntöpyöräksi korvautui 90 mm:llä. Samasta syystä
akselit ovat M5 eivätkä M4. U624ZZ-urarullat on ostettu ennen kiskon vaihtoa ja
ne jäävät varastoon.

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

**Kisko on 2020 V-slot -alumiiniprofiili**, ja vaunu kulkee sillä POM-V-pyörillä.
Se on sama pari jota jokainen Ender-luokan 3D-tulostin käyttää: massatuotettu,
mitoitettu ja halpa, eikä siinä ole mitään keksittävää.

| | |
|---|---|
| Kisko | 2020 V-slot, 1,5–2,5 m |
| Vaunun pyörät | POM V-ura, 625ZZ-laakeri, 3–4 kpl vaunua kohti |
| Akselit | **M5** — 625ZZ on 5 × 16 × 5 |
| Kääntöpyörä | 90 mm laakeroitu vaijeripyörä |
| Vetopyörä | 41 × 16 × 6 mm, ura 3–5 mm hihnalle, moottorin akselilla |

**Eksentriset välikkeet ovat pakollisia, eivät valinnaisia.** Vakiorakenne on
2–3 kiinteää pyörää ja yksi eksentrinen, jolla väljyys kiskoa vasten ajetaan
pois. Ilman niitä vaunu joko heiluu tai jumittaa, eikä sitä voi säätää
jälkikäteen millään. Ne myydään erikseen (`eccentric spacer M5 2020`).

**Kääntöpyörän halkaisija ei vaikuta nopeuteen** — vain vetopyörä esiintyy
laskussa. Sen saa siis mitoittaa vapaasti taivutussäännön mukaan: nyrkkisääntö
on ~10 × hihnan paksuus eli vähintään 50 mm 5 mm hihnalle, ja 90 mm ylittää sen
selvästi. Vetopyörän 41 mm alittaa säännön, ja se on tietoinen kompromissi —
pyörä on hyllyssä ja moottorin akselilla, ja sen vaihtaminen muuttaisi nopeutta.

**Hihnan kiristys kuuluu kääntöpyörän päähän.** PU-pyörähihna hitsataan
umpinaiseksi silmukaksi eikä sen pituutta voi jälkikäteen säätää, joten
kannakkeeseen tarvitaan pitkittäinen säätöura. Se on halpa piirtää nyt ja
kallis korjata sitten.

### Mitä tämä korvasi, ja miksi se kannattaa tietää

Alkuperäinen ratkaisu oli **U624ZZ-urarullat 4 mm pyörötangolla tai 3 mm
kireällä vaijerilla**, akselina M4. Se kaatui jännevälistä: 4 mm tanko notkuu
2 m matkalla ja vaatii 3–4 välitukea, kun rata on mitoitettu 1,5–2,5 metrille.
2020-profiili tulee toimeen päätytuilla ja korkeintaan yhdellä keskituella.

Välissä harkittiin **kumi- tai PU-rullia peltiä vasten**. Se ratkaisi
jäykkyyden mutta toi kaksi uutta ongelmaa: tasainen pinta ei keskitä mitään,
joten sivuttaisohjaus olisi pitänyt rakentaa erikseen, ja kumi vierii
raskaammin kuin POM — merkitsevää, koska teholähde on rajatapaus.

**Rulla seuraa kiskosta, ei toisin päin.** Tämä kiersi kolme kertaa juuri siksi
että rullaa valittiin ensin: U-ura vaatii pyöreän kiskon, V-ura profiilin,
sileä kehä tasaisen pinnan. Ne ovat kolme eri rataa, eivät kolme rullaa samalle
radalle.

U624ZZ:t on ostettu (10 kpl) ja ne jäävät varastoon.

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

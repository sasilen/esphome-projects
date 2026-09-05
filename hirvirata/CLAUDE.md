# CLAUDE.md — Hirvirata (ESPHome)

> **Tekninen viitedokumentti: nykytila ja perustelut.** Yleiskuva: [README.md](README.md).

Liikkuva maalitaulurata ilmakivääri- ja pienoisradalle. ESP8266 ohjaa
vaihdemoottoria H-siltaohjaimen kautta; hihna vetää vaunua kiskolla
edestakaisin eri nopeuksilla ja ohjelmilla. Kotiautomaatio-integraatio
Home Assistantiin ESPHome-APIn yli.

Käyttäjä kommunikoi suomeksi. Vastaa suomeksi, myös koodikommenteissa.

## Projektin tila

Suunnitteluvaihe. YAML-luonnos on olemassa, rautaa ei ole vielä koottu.
Kolme mittausta on **tekemättä** ja ne voivat muuttaa komponenttivalintoja:

1. Moottorin akselin halkaisija (hihnapyörän reikä on kiinteä 6 mm)
2. Moottorin jumivirta (jos > 2 A → L298N vaihtuu BTS7960:een)
3. Moottorin kiinnitysreikien jako
4. U624ZZ-rullien uran mitat (valmistajakohtaiset — 4 mm tanko ei aina istu)

Älä oleta näiden tuloksia. Jos jokin niistä on ratkaiseva vastauksen
kannalta, sano se suoraan.

## Rauta

| Osa | Tiedot |
|---|---|
| Ohjain | Wemos D1 mini (ESP8266) tai mikä tahansa ESP32. Ks. "Ohjainvalinta" |
| Moottoriajuri | ARCELI L298N -moduuli (5 kpl varastossa) |
| Moottori | 12 V vaihdemoottori, 200 rpm, ikkunanavaajatyyppi |
| Hihnapyörä | 41 × 16 × 6 mm, alumiini, yksi ura, kiinteä 6 mm reikä |
| Hihna | 5 mm PU-pyörähihna, päät hitsataan |
| Teholähde | Newding 12 V / 2 A pistokemuuntaja, 5,5 × 2,1 mm jakki. **Rajatapaus** |
| ESP:n virta | LM2596 buck 12 V → 5,0 V |
| Vaunun rullat | U624ZZ, 4 × 13 × 7 mm, U-ura, 10 kpl. **Eivät** kelpaa hihnapyöräksi |

## Ohjainvalinta

Kumpi tahansa käy. Alusta vaikuttaa vain `output:`-blokkiin ja pinneihin —
`fan:`, `script:` ja `select:` ovat identtiset.

**Wemos D1 mini (ESP8266)** on ensisijainen. PWM on ohjelmallinen
(`esp8266_pwm`, ajastinkeskeytys), mutta 1 kHz:llä moottorinohjauksessa
jitteri on merkityksetön. Molemmilla PWM-lähdöillä **täytyy** olla sama
taajuus — ne jakavat saman ajastimen.

**ESP32** (WROOM, WROVER, C3, S2, S3) käyttää LEDC-hardware-PWM:ää. Ei
välttämätön parannus tähän käyttöön, mutta ei myöskään haittaa.

## Pinnijärjestys

Lyöty lukkoon. Älä siirtele ilman pyyntöä.

### D1 mini (ESP8266)

| Pinni | GPIO | Käyttö |
|---|---|---|
| D1 | 5 | PWM → L298N IN1 |
| D2 | 4 | PWM → L298N IN2 |
| D5 | 14 | Rajakytkin vasen (INPUT_PULLUP, inverted) |
| D6 | 12 | Rajakytkin oikea (INPUT_PULLUP, inverted) |

Vältä D3 (GPIO0), D4 (GPIO2) ja D8 (GPIO15) — käynnistysvastukset. D0
(GPIO16) ei tue PWM:ää eikä sisäistä pullupia. Virta 5 V -pinniin buckilta.

### ESP32 (vaihtoehto)

| GPIO | Käyttö |
|---|---|
| 25 | PWM → L298N IN1 |
| 26 | PWM → L298N IN2 |
| 32 | Rajakytkin vasen (INPUT_PULLUP, inverted) |
| 33 | Rajakytkin oikea (INPUT_PULLUP, inverted) |

### Yhteistä

PWM menee **IN-tuloihin**, ei ENA:han — ENA-hyppyjohdin jää paikalleen.
Taajuus 1000 Hz; L298N on bipolaarinen eikä kestä yli ~15 kHz tuottamatta
lämpöä. 3,3 V logiikkataso riittää L298N:n TTL-tuloille (HIGH-kynnys 2,3 V,
kun Vss = 5 V).

## Ohjelmistoarkkitehtuuri

- Moottori on `fan:` `platform: hbridge`, id `moottori`, `decay_mode: slow`,
  `speed_count: 100`. Suunta tulee fanin FORWARD/REVERSE-tilasta.
- Nopeus- ja suunnanvaihdot tehdään lambdalla suoraan fan-callilla, ei
  `fan.turn_on:`-actionin templateilla — se on osoittautunut luotettavammaksi:
  ```cpp
  auto call = id(moottori).turn_on();
  call.set_speed(nopeus);
  call.set_direction(eteen ? FanDirection::FORWARD : FanDirection::REVERSE);
  call.perform();
  ```
- Kaikki ajoliikkeet kulkevat apuscriptin `aja(nopeus, eteen, kesto)` kautta.
  Kutsuva ohjelma odottaa aina `script.wait: aja`.
- `aja` sisältää **pehmeän käynnistyksen**: 50 % → 75 % → 100 % kolmessa
  100 ms:n askeleessa. Tämä on pakollinen 2 A:n teholähteellä, ei
  kosmeettinen. Ilman sitä käynnistyspiikki notkauttaa 12 V:n ja
  buckin takana oleva ESP saattaa bootata kesken ajon. Kokonaiskesto
  säilyy: rampin 300 ms vähennetään loppuviiveestä.
- Ajo-ohjelmat ovat omia scriptejään, `mode: restart`. Nykyiset:
  `ohjelma_tasainen`, `ohjelma_satunnainen`, `ohjelma_kiihtyva`.
- `seis`-script pysäyttää **kaikki** ohjelmascriptit ja `aja`:n, sitten
  `fan.turn_off`. Rajakytkimet ja hätäseis-nappi kutsuvat sitä.
- Ohjelman valinta on `select:` `platform: template`, jonka `set_action`
  julkaisee tilan, ajaa `seis`:in, odottaa 300 ms ja käynnistää valitun
  scriptin lambdalla.

### Uuden ajo-ohjelman lisääminen

1. Uusi script, `mode: restart`, rakentuu `script.execute: aja` +
   `script.wait: aja` -pareista.
2. Nimi `select`-komponentin `options`-listaan.
3. Haara `set_action`in lambdaan.
4. `script.stop`-rivi `seis`-scriptiin. **Tämä unohtuu helposti** — ilman
   sitä rajakytkin ei pysäytä uutta ohjelmaa.

## Kalibrointi ja vakiot

- Efektiivinen hihnapyörän halkaisija **37 mm** (41 mm ulkomitta miinus
  hihnan uppouma uraan). Täysi nopeus ≈ 0,39 m/s.
- Nopeussensorin kerroin `0.39` on laskennallinen. Kalibroi ajamalla vaunu
  tunnettu matka täydellä teholla ja sekuntikellolla; ero paljastaa myös
  hihnan luiston.
- `perusnopeus`-numberin `min_value: 20` on arvaus. Vaihdemoottori ei
  todennäköisesti lähde liikkeelle alle 25–30 %:lla — nosta kokeilun jälkeen.
- PWM ei ole lineaarinen kuorman alla. Nopeussensori on arvio, ei mittaus.

## Tunnetut riskit

- **L298N on heikoin lenkki.** Jännitehäviö 1,5–2 V (moottori saa ~10 V),
  virrankesto ~2 A/kanava hyvällä jäähdytyksellä. Jos jumivirta on liian
  suuri, vaihtoehdot järjestyksessä: (a) rinnankytke molemmat kanavat
  IN1→IN3, IN2→IN4, OUT1+OUT3, OUT2+OUT4, (b) vaihda BTS7960/IBT-2:een.
  Sama YAML toimii BTS7960:ssä muuttumattomana.
- **Älä syötä ESP32:ta L298N:n 5 V -lähdöstä.** Se on 78M05-lineaari­
  regulaattori ja WiFi-virtapiikit nollaavat ESP:n.
- Yhteinen GND ESP:n, L298N:n ja teholähteen välillä on pakollinen.
- **Teholähde 12 V / 2 A on rajatapaus.** Ajovirta 0,3–0,5 A riittää hyvin,
  mutta käynnistyspiikki on 3–5-kertainen eikä pistokemuuntajassa ole
  kunnollista rajoitusta. Pehmeä käynnistys + 2200 µF hoitavat tämän.
  Jos ESP bootaa uudelleen ajon aikana, syy on tässä — ei WiFissä.
- 2200 µF 12 V:n riviin mahdollisimman lähelle L298N:ää (ei 1000 µF, koska
  teholähteessä ei ole marginaalia) + 100 nF suoraan moottorin napojen
  väliin, moottorin päässä eikä ajurin päässä. Kipinöinti häiritsee WiFiä.
- Pyöreä akseli ilman litteää kohtaa → hihnapyörä luistaa ensimmäisen
  suunnanvaihdon jälkeen. Viilaa lovi kuusiokoloruuvin alle.
- PU-hihna venyy käytössä. Jousikiristin tai siirrettävä kääntöpyörä.
- Suunnanvaihto täydellä nopeudella rasittaa vaihteistoa ja piikittää
  virran. Ohjelmissa aina pysähdys ja tauko suunnanvaihdon välissä.
- ESP8266:lla eri taajuudet kahdella `esp8266_pwm`-lähdöllä käyttäytyvät
  arvaamattomasti — sama ajastin. Pidä molemmat 1000 Hz:ssä.

## Mekaniikka

- **U624ZZ ei kelpaa kääntöpyöräksi.** 13 mm ulkohalkaisija on liian pieni
  5 mm PU-hihnalle; nyrkkisääntö on ~10× hihnan paksuus eli vähintään
  50 mm. Kääntöpyöräksi tarvitaan toinen samanlainen 41 mm hihnapyörä.
- U624ZZ:t ovat **vaunun ohjausrullia**. U-ura on tarkoitettu pyöreälle
  kiskolle: 4 mm terästanko tai 3 mm kireä teräsköysi. Ei sovi 2020-
  alumiiniprofiiliin, joka vaatii V-uran.
- Akselina M4-pultti (sisäreikä 4 mm), aluslevyt välikkeiksi. Kolme rullaa
  vaunua kohti: kaksi tangon päälle, yksi alle.
- 4 mm tanko notkuu 2 m matkalla — tue 3–4 kohdasta.

## Mitoitusrajoite

200 rpm ja 37 mm efektiivinen halkaisija antavat 0,39 m/s. Virallisen
juoksevan hirven nopeus on 4–5 m/s, mihin tarvittaisiin ~40 cm pyörä
(jolloin vääntö loppuu) tai selvästi nopeampi moottori. Tämä rata on
mitoitettu **1,5–2,5 m kulkuaukolle** pienoisrata- ja ilmakivääri­
harjoitteluun. Älä ehdota täysmittaista nopeutta nykyisellä moottorilla.

## Turvallisuus

Rajakytkimet molemmissa päissä ovat pakollisia, eivät valinnaisia. Ilman
niitä vaunu ajaa päätyyn ja moottori jää jumiin täydellä virralla — se
polttaa L298N:n ja mahdollisesti moottorin. Kaikki muutokset scriptien
pysäytyslogiikkaan pitää tarkistaa tätä vasten.

Sulake 12 V:n plussaan, 3 A riittää 2 A:n teholähteelle.

DC-jakkiliitin ruuviliittimillä (5,5 × 2,1 mm naaras) teholähteen päähän,
jotta johtoa ei tarvitse katkaista.

## Tyyli

- YAML-tunnisteet ja käyttöliittymänimet suomeksi.
- Konfiguraatio yhtenä `hirvirata.yaml`-tiedostona, ei paketteja jaettuna —
  projekti on tarpeeksi pieni.
- Salasanat `!secret`-viittauksilla, ei koskaan tiedostoon kirjoitettuna.

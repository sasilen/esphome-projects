# Axioma Effectio (Qalcosonic W1) → Home Assistant (ESPHome + CC1101)

> **Tekniset tiedot ja perustelut.** Yleiskuva: [README.md](README.md).

## Tavoite

Lukea **Axioma Effectio / Qalcosonic W1** -vesimittaria suoraan Home Assistantiin käyttäen:

- ESP32
- CC1101 868 MHz
- ESPHome API

**Ei MQTT:tä.**

---

# Mittarin tiedot

Kuvan perusteella:

| Ominaisuus | Arvo |
|------------|------|
| Valmistaja | Axioma |
| Malli | Effectio / Qalcosonic W1 |
| SW | 1.03 |
| CE | M24 1621 |
| Tyyppi | LT-1621-MI001-034 |
| SN | 12345678 — paikanpitäjä, oikea lukee tyyppikilvestä |
| Valmistusvuosi | 2024 |

Todennäköinen Meter ID:

```
12345678
```

Huom:
Meter ID varmistetaan myöhemmin vastaanotetusta Wireless M-Bus -telegrammista.

---

# Käytettävät laitteet

## Jo olemassa

- ESP32 DevKit, 30-nastainen — [kuva](../pegasos.enervent/esp32-devkit.jpg)
- CC1101 868 MHz — [kuva](cc1101-module.jpg)
- 868 MHz SMA-antenni
- ESP8266 (ei tarvita tähän projektiin)

## Miksi ESP32 eikä ESP8266

**Ohjelma ei mahdu ESP8266:een.** Valmis image on 1 069 167 tavua, ja D1 minin
sovelluspartitio on OTA:n kanssa noin megatavu. Se ei ole rajatapaus, ja se on
mitattu eikä arvioitu — luvut ja niiden vertailu repon muihin projekteihin ovat
kohdassa "Alustatuki".

Komponentti ei muutenkaan tue ESP8266:ta, mutta koko olisi ratkaissut asian
vaikka tukisi.

**Levy on tavallinen 30-nastainen DevKit**, printtiantennilla, USB-C:llä ja
CH340C-siltapiirillä. Viisi nastaa riittää, ja niitä on kolmekymmentä.

**Ulkoantennia ei tarvita.** wM-Bus on radio: mittari lähettää 868 MHz:llä ja
CC1101 kuulee sen kantaman sisältä mistä tahansa, joten **vastaanottimen paikan
valitsee itse** ja sen valitsee sieltä missä WiFi kuuluu. Aidonissa vastaava
pakko on aito, koska se levy on fyysisesti kiinni mittarin portissa — täällä ei
ole.

Siksi levylle tulee **vain yksi antenni: 868 MHz CC1101:lle.** Se poistaa
sekaannuksen jota tässä tiedostossa aiemmin varoiteltiin, kun levyvaihtoehtona
oli u.FL-antennia vaativa moduuli ja antenneja oli kaksi.

**CC1101-moduulissa on 26 MHz:n kide**, mikä on odotettu arvo.

**Antennikytkentä: pigtail tuli moduulin mukana.** Kuvatussa kulmassa ei näy
SMA- eikä u.FL-liitintä, joten antenni kytkeytyy sen kautta. Tämä on siis
kunnossa eikä sovitinta tarvita.

Jos pigtail joskus katoaa, neljännesaallon lanka on 868 MHz:llä noin 8,2 cm ja
kelpaa kokeiluihin ilman mitään liitintä.

### 8,2 vai 8,6 cm — molemmat ovat oikein, eri oletuksella

Lähteet antavat neljännesaallolle **8,6 cm** ja tässä tiedostossa on lukenut
**8,2 cm**. Kumpikaan ei ole virhe:

```
λ    = 299 792 458 / 868,95 MHz = 34,50 cm
λ/4  = 8,63 cm                              vapaassa tilassa
     × 0,95 nopeuskerroin                   eristetyllä langalla
     = 8,19 cm
```

**8,6 cm on teoreettinen vapaan tilan mitta, 8,2 cm on eristetylle langalle
lyhennetty.** Jos leikkaat paljasta lankaa, käytä 8,6 cm; jos eristettyä,
8,2 cm on lähempänä. Ero on puoli senttiä eikä ratkaise mitään vastaanotossa —
mutta se selittää miksi kaksi lähdettä antaa eri luvun.

**Ja vastaanotossa viritys on vähemmän kriittinen kuin lähetyksessä.** Huono
sovitus heikentää herkkyyttä, mutta ei riko mitään — lähettävässä päässä
heijastunut teho voi rikkoa. Tämä solmu ei lähetä koskaan.

### Kolme lukua linkkibudjettiin

| | |
|---|---|
| RX-herkkyys | noin **−110 dBm** |
| RX-virta | ~14 mA |
| Datanopeus | 0,6–600 kbps — wM-Bus T1 on 100 kbps, hyvin sisällä |

−110 dBm on se luku jota vasten kuuluvuutta arvioidaan, jos mittari ei kuulu.
Vertailun vuoksi WiFi lukee tällä levyllä −56 dBm työpöydällä.

### Lähetysrajoitus ei koske tätä

EU:n 868 MHz -kaista on **1 %:n lähetysaikarajoitettu**, ja se on syytä tuntea
— mutta se ei rajoita mitään täällä, koska tämä solmu **ei lähetä koskaan.**
Kuuntelu on rajoittamatonta.

Mittarin ~16 sekunnin lähetysväli ei myöskään johdu siitä: telegrammi kestää
millisekunteja, joten sen käyttöaste on promillen luokkaa. Väli on
paristonkeston valinta, ei sääntelyn pakko.

---

# Arkkitehtuuri

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

Ei MQTT:tä.

---

# ESP32 ↔ CC1101 kytkentä

Piirretty auki: [`wiring.svg`](wiring.svg).

| CC1101 | ESP32 | |
|---------|-------|---|
| VCC | 3.3V | |
| GND | GND | |
| SI (MOSI) | GPIO23 | |
| SO (MISO) | GPIO19 | |
| SCK | GPIO18 | |
| CSN | GPIO5 | strapping |
| GDO0 | GPIO4 | `irq_pin` |
| GDO2 | — | **ei kytketä** |

## Huomio

CC1101 toimii vain 3.3 voltilla.

Älä koskaan käytä 5V.

## DevKitissä D-numero on GPIO-numero

Levyn silkkipainatus ei sano `GPIO18` vaan `D18`, ja **se on sama nasta.**
Ylärivi lukee kokonaisuudessaan:

```
3V3  GND  D15  D2  D4  D16  D17  D5  D18  D19  D21  RX0  TX0  D22  D23
```

**Tämä on eri kuin Wemos D1 minissä**, ja siinä on ansa jota tässä repossa on
kaksi levytyyppiä: D1 minissä `D5` on **GPIO14** eikä numeroilla ole mitään
yhteyttä toisiinsa. ESP32-DevKitissä `D`-etuliite on pelkkä etuliite. Kuka
tahansa joka siirtyy levystä toiseen tekee tämän virheen kerran.

| YAML | Levyn merkintä |
|---|---|
| `clk_pin: GPIO18` | `D18` |
| `mosi_pin: GPIO23` | `D23` |
| `miso_pin: GPIO19` | `D19` |
| `cs_pin: GPIO5` | `D5` |
| `irq_pin: GPIO4` | `D4` |

**Kaikki seitsemän lankaa menevät samaan riviin.** 3V3 ja GND ovat sen kaksi
ensimmäistä, D23 reunimmainen — alariviin ei tarvitse koskea lainkaan, mikä
helpottaa sekä juottamista että kotelointia.

## Moduulissa ei ole nastamerkintöjä kummallakaan puolella

Levy on pieni neliö, silkkipainatuksena vain `CC11010 868MHz Module`. Kahdeksan
reikää yhdessä reunassa, kolme vastakkaisessa, **eikä yhtään nastan nimeä.**
Järjestys on siis tunnistettava, ei luettava.

**Kaksi riippumatonta lähdettä antaa saman järjestyksen**, ja molemmat kuvaavat
fyysisesti tätä levyä — sama silkkipainatus, sama 8 + 3 reikää. Yleinen
"CC1101-moduulin pinout" -taulukko, joka kuvaa 10-nastaista korttia eri
järjestyksessä, **ei päde tähän** ja hylättiin siksi.

Asento ratkaistaan maamerkeistä, koska levyn saa käteen neljässä asennossa:
**kide ylöspäin ja teksti vasemmassa reunassa pystyssä.** Silloin kahdeksan
reikää ovat oikeassa reunassa ja järjestys ylhäältä alas on:

| # | Nasta | → ESP32 |
|---|---|---|
| 1 | CSN | GPIO5 |
| 2 | GDO0 | GPIO4 |
| 3 | GDO2 | **ei kytketä** |
| 4 | MISO | GPIO19 |
| 5 | SCK | GPIO18 |
| 6 | MOSI | GPIO23 |
| 7 | GND | GND |
| 8 | VCC | 3V3 |

Vasemmassa reunassa **GND — ANT — GND**; keskimmäinen on antenni, ja järjestys
on symmetrinen eli kääntövirhe ei sotke sitä.

Piirretty auki: [`wiring.svg`](wiring.svg).

**Reikien jako on 2,0 mm eikä 2,54 mm**, joten Dupont-hyppylangat eivät mahdu.
Juota langat suoraan — ohutta, 0,2 mm² monisäikeistä tai AWG30:tä, koska paksu
lanka repii pienen padin irti. Pysyvässä asennuksessa juotos on muutenkin
parempi kuin liitin, mikä on sama päättely kuin stiebelin väyläjohtimissa.

### Ja tämä on syy miksi taulukkoon saa luottaa tässä

**Vain VCC ja GND voivat rikkoa piirin.** Loput kuusi ovat 3,3 V:n logiikkaa,
joten väärä arvaus niissä tarkoittaa että mikään ei toimi — ei että jokin
hajoaa. Riski on siis kahdessa nastassa, ei kahdeksassa.

Ne kaksi tunnistaa mittarilla ilman mitään lähdettä: **niiden väliltä
vastuslukema nousee hitaasti** ohituskondensaattorien varautuessa, kun taas
logiikkanastat lukevat auki lähes kaikkeen. Jos pari löytyy rivin siitä päästä
jonka taulukko lupaa, koko asento on todistettu yhdellä mittauksella.

Sama menetelmä kuin stiebelissä, jossa TJA1050:n nastat tunnistettiin kolmella
riippumattomalla jatkuvuusmittauksella ennen kuin mitään kytkettiin.

### SPI-kello on 1 MHz, ja se näkyy lokissa

Boottiloki tulostaa `data_rate: 1000000.0`. Se on SPI-väylän nopeus, ei radion
bittinopeus. CC1101 kestäisi 10 MHz, mutta 1 MHz on se jota lähteet
suosittelevat kehitykseen ja se jonka komponentti valitsee itse — tähän ei
tarvitse koskea.

## Strapping-nastat, ja miksi vain toinen niistä on ongelma

Piiri lukee tietyt GPIO:t **nollauksen hetkellä** päättääkseen käynnistystilan.
Sen jälkeen ne ovat tavallisia nastoja, joten strapping-nastan saa käyttää —
kunhan mikään ei pidä sitä väärässä tasossa juuri silloin. Tavallisen ESP32:n
strapping-nastat ovat **GPIO0, 2, 5, 12 ja 15**, ja tämä kytkentä osuu kahteen.

**GPIO5 on turvallinen.** Se haluaa HIGH:n käynnistyksessä, ja CS lepää
HIGH:ssa. Sama päättely on kirjattu
[stiebelissä](../stiebel.eltron/CLAUDE.md) saman piirin osalta.

**GPIO2 ei ole, ja siksi GDO2 jää kytkemättä.** Se haluaa LOW:n tai kellumisen,
ja GDO2 on CC1101:n **lähtö** — jos se ajaa nastaa ylös nollauksen aikana, levy
ei käynnisty normaalitilaan. Skeemamuutos poisti GDO2:n käytöstä ilman että
kukaan tavoitteli tätä, mutta **johtoa ei silti pidä jättää paikalleen**: tämän
tiedoston oma vianetsintä listaa boot-loopin syyksi nimenomaan väärässä nastassa
olevan GDO-linjan.

---

# CC1101 pinout

Useimmissa moduuleissa pinnit ovat:

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

Tarkista kuitenkin oman moduulin silkkipainatus.

---

# ESPHome testikonfiguraatio

> **Tämä on `version_4`:n skeema eikä käänny nykyisellä komponentilla.** Se on
> jätetty paikalleen koska se on toisen sukupolven oikea muoto, ei virhe — ks.
> "Versiot ovat kaksi sukupolvea". Ajettava versio on
> [`axioma.effection.yaml`](axioma.effection.yaml).

```yaml
esphome:
  name: vesimittari

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

# Mitä pitäisi näkyä logissa

Kun mittari lähettää telegrammin, loggeriin tulee esimerkiksi:

```
Received T1 A frame from 12345678 RSSI -70
```

Jos tämä näkyy:

- radio toimii
- kytkennät ovat oikein
- taajuus on oikein
- mittari kuuluu vastaanottimeen

---

# Avoin: miksi kehyksiä ei tule

**Radio toimii — se on todistettu.** Kytkettynä ja parin metrin päässä
mittarista loki tuotti:

```
[D][packet:106]: Have data from radio (8 bytes)
[D][wmbusmeters:351]: raw packet "320C800948884A28"
```

**SPI ja GDO0 ovat tässä kunnossa**, ja perustelu on vahvempi kuin pelkkä rivin
ilmestyminen: vaihtelevat tavut eivät voi tulla kuolleelta väylältä, koska
vastaamaton MISO lukee tasaista nollaa tai `0xFF`:ää. Keskeytyslinja laukeaa ja
FIFO:sta luetaan oikeasti dataa.

**Se ei tarkoita että vastaanottopolku kokoaa kehyksiä.** Kolmessa minuutissa
tuli yksi kahdeksan tavun paketti, eikä siinä ole telegrammia: `0x32` ja `0x0C`
eivät ole L- ja C-kenttiä lainkaan vaan dekoodaamatonta chip-tason dataa, ja
kahdeksan tavua on juuri se vakio jonka epäonnistunut otsikon purku tuottaa —
perustelu on kohdassa "Niiden 47 paketin otsikkoanalyysi ei ollut pätevä".
Tässä luki aiemmin että `0x0C` on kelvoton C-kenttä; se luki kenttää väärästä
paikasta.

**Kahden metrin päässä kuuluvuus ei selitä hiljaisuutta.** Oman mittarin
telegrammin pitäisi tulla vahvana ja kokonaisena. Antenni on kiinni ANT-padissa,
ja se on kierteinen kuparilanka eli heliksiantenni — säteilijä, ei pelkkä
siirtolinja.

Jäljelle jää **kolme** kysymystä eikä yksi, ja ne on eroteltava toisistaan:
lähettääkö mittari, lähettääkö se moodissa jota tämä komponentti osaa, ja
kokoaako komponentti kehyksen jos lähetys tulee. Ne ovat hypoteesit 2, 1 ja 3
alla. **Yksikään mittaus ei tähän mennessä ole erottanut niitä**, koska
kaikki kolme näyttävät lokissa samalta.

## Siitä on tässä repossa kokemusta

Aidonin koko projekti alkoi samasta:

> **Portti on oletuksena kuollut.** Verkkoyhtiön on aktivoitava sekä rajapinta
> että 5 V:n syöttö. Tämä on projektin ainoa vaihe jota ei voi nopeuttaa —
> tilaa se ensin.

Vesimittarissa on sama mahdollisuus, mutta muoto on eri: **kyse ei ole
kävelyluennasta vastaan kiinteä verkko.** Sama laite lähettää 16 sekunnin välein
aikatauluikkunan sisällä ja on hiljaa sen ulkopuolella, ja oletusikkuna on
**ma–pe 6:00–18:00.** Kumpi luentatapa on käytössä ei siis ratkaise mitään —
kellonaika ratkaisee.

Tämän tiedoston **`noin 16 sekunnin väli` on yleisestä lähteestä eikä mitattu
tästä yksilöstä.** Se on oletus siinä missä ne taulukot joita tässä projektissa
on jouduttu kumoamaan neljä kertaa. Maahantuojan myyntimateriaali sanoo
lähetysväliksi **5 minuuttia**, mikä on ristiriidassa 16 sekunnin kanssa —
kumpaakaan ei ole todennettu tästä mittarista, ja NFC-luku kertoisi sen.

**Kysy se samalla kun kysyt AES-avainta.** Kaikkiin menee kalenteriaikaa ja
kaikki menevät samalle vastaanottajalle:

1. **Onko `wMBus T1` päällä lainkaan — ja voitteko kytkeä sen päälle?**
2. Missä moodissa se lähettää — T1, C1 vai S1?
3. AES-128-avain

Kohta 1 muuttui muodosta "onko radiolähetys päällä" tähän, kun selvisi että
**mittari on LoRaWAN-luennassa.** Silloin kysymys ei ole onko radio päällä
vaan onko *tämä* radio päällä, ja vastaus on todennäköisesti ei — ks. "Ratkaisu
on todennäköisesti tämä". Se tekee kohdasta 1 pyynnön muuttaa asetusta heidän
omassa laitteessaan, ja **kieltävä vastaus on siinä rehellinen mahdollisuus**
paristoperustelulla.

Kohta 2 on yhä listalla, koska se on ainoa joka voi kaataa rautavalinnan: T1 ja
C1 tulevat samalla kuuntelulla, S1 vaatii toisen vastaanottimen.

**Älä esitä johtopäätöstä "mittari ei lähetä"** vaan kysy neutraalisti. Tämän
tiedoston oma päättely siitä on jouduttu peruuttamaan kahdesti, ja
vastaanottimen puolella on yhä avoin epäilty — ks. hypoteesi 3.

Pyyntöön kuuluu **tyyppikilven oikea sarjanumero.** Repossa se on paikanpitäjä
`12345678`, koska repo on julkinen.

## Yön mittaus ei ratkaissut sitä: se osui lähetysikkunan ulkopuolelle

8,5 tuntia parin metrin päässä mittarista, taajuudella 868,95 MHz:

| | |
|---|---|
| Kokonaisia kehyksiä | **0** |
| Raakapaketteja | 47 |

**Nolla on tässä odotettu tulos eikä havainto.** Qalcosonic W1:n oletusaikataulu
on **ma–pe 6:00–18:00**, ja sen ulkopuolella radio on hiljaa kokonaan — paristo
mitoitetaan 15 vuodeksi. Mittaus alkoi sunnuntaina noin 21:15 ja päättyi
maanantaina 05:45, eli se oli kokonaan ikkunan ulkopuolella ja viikonloppuna
kahdesti.

Aikataulu on maskitettu sekä viikonpäivä- että kuukausitasolla. Lähde ei ole
valmistajan datalehti vaan riippumaton rakentaja joka törmäsi täsmälleen tähän
oireeseen, ja wmbusmetersin ylläpitäjä vahvistaa ilmiön yleisyyden: osa
mittareista sammuttaa radion öisin ja viikonloppuisin oletuskonfiguraatiolla.
Maskit ovat luettavissa mittarista NFC:llä, joten oletus on tarkistettavissa
laitteesta — ks. "Mittarin oma konfiguraatio on luettavissa NFC:llä".

**Vertailuluku pätee silti, kun mittaus tehdään ikkunan sisällä.** Kahden metrin
päässä 16 sekunnin välein lähettävä mittari tuottaisi noin 1900 vastaanottoa
8,5 tunnissa.

### Niiden 47 paketin otsikkoanalyysi ei ollut pätevä

Tässä luki että neljä ominaisuutta yhdessä osoittavat kaikki 47 kohinaksi.
Johtopäätös osuu todennäköisesti oikeaan, mutta **kaksi neljästä perustelusta
ei mittaa sitä mitä se väittää.**

`packet.cpp` yrittää T1:n 3-of-6-dekoodausta kolmesta ensimmäisestä tavusta. Jos
yksikin kuuden bitin koodi on kelvoton, dekoodaus palauttaa tyhjän ja L-kenttä
palaa oletusarvoon 0 — ja siitä `expected_size` laskee `(3·5+1)/2 =` **8**.
Satunnaisdatalla dekoodaus läpäisee noin 0,4 %:n todennäköisyydellä, joten
käytännössä jokainen kohinaosuma tuottaa saman luvun.

Kaksi seurausta:

- **8 tavua ei ole lukugranulariteetti vaan laskettu vakio.** Se on komponentin
  allekirjoitus tilanteelle "en saanut otsikkoa auki" eikä kerro signaalista
  mitään suuntaan tai toiseen.
- **Lokiin tulostetut tavut eivät ole L- ja C-kenttiä.** `convert_to_frame`
  yrittää dekoodausta vasta myöhemmin ja kaatuu samalla tavalla, joten
  tulosteessa on dekoodaamatonta chip-tason dataa. Väite "yksikään C-kenttä ei
  kelpaa" lukee kenttää joka ei ole siinä paikassa. Tämän voi tarkistaa lokin
  omalla esimerkillä: `0x32 = 0b00110010`, ja `>>2 = 0b001100` ei ole
  3-of-6-hakutaulussa, eli dekoodaus kaatuu jo ensimmäiseen segmenttiin.

Jäljelle jää kaksi kelvollista perustelua: paketit ovat eri sisältöisiä eikä
niissä ole rytmiä. Ne riittävät sanomaan ettei mikään lähde toistu, mutta
**eivät erota kohinaa oman mittarin kehyksestä jonka otsikon purku
epäonnistui.**

Tämä on sama opetus kolmatta kertaa tässä tiedostossa: **taulukko on hypoteesi,
laitteen oma sanoma on todiste** — ja tällä kerralla väärä taulukko oli oma.

### Hypoteesi 1: väärä taajuus — ei testattavissa tällä komponentilla

868-kaistalla on kaksi wM-Bus-moodia, ja kuuntelemme vain toista:

| Moodi | Taajuus |
|---|---|
| **S** | **868,30 MHz** |
| T, C | 868,95 MHz |

**Tässä luki että hypoteesi on testattu ja kumottu 7.9.2026. Se peruutetaan:
testi oli kyvytön havaitsemaan sitä mitä se väitti sulkevansa pois.**

`transceiver_cc1101.cpp` kirjoittaa koko rekisteritaulukon kiinteillä
literaaleilla, ja `frequency`-asetuksesta johdetaan **vain** FREQ2/FREQ1/FREQ0:

| Asetus | Rekisteri | |
|---|---|---|
| 100 kbps | MDMCFG4 `0x5C`, MDMCFG3 `0x04` | kiinteä |
| 2-FSK, Manchester **pois**, 16/16 sync | MDMCFG2 `0x06` | kiinteä |
| Deviaatio ~50 kHz | DEVIATN `0x44` | kiinteä |
| Sync word `0x543D` | SYNC1/SYNC0 | kiinteä |

Koodin oma kommentti sanoo sen suoraan: `Configure for wM-Bus Mode C/T at
868.95 MHz, 100 kbps, 2-FSK`.

**`frequency: 868.30MHz` siirsi siis pelkän paikallisoskillaattorin.** S-moodi on
32,768 kbps **Manchester-koodattuna** ja eri synkronointikuviolla; vastaanotin oli
100 kbps 2-FSK ilman Manchesteria. Se ei demoduloi S-lähetystä millään
signaalinvoimakkuudella.

Samasta syystä myös selitys jota tässä kokeiltiin — "S-moodi on kohinaisempi
kanava, koska sen eri modulaatio- ja nopeusasetukset laukaisevat väärän
synkronoinnin herkemmin" — ei voi olla oikea: **yhtään modulaatio- tai
nopeusasetusta ei vaihtunut.** Ja 43 minuutin ajo 868,30:llä tuotti
myöhemmin **nolla** raakapakettia, mikä on päinvastainen havainto kuin se kuuden
minuutin otos jolla kohinaisuutta perusteltiin.

**Komponentti ei tue S-moodia lainkaan.** Radiokerros asettaa link moden vain
arvoihin C1 tai T1, ja `wmbus_meter`:n `mode:`-valinnat ovat `Any`, `C1` ja `T1`.
Tätä hypoteesia ei siis voi testata tällä raudalla: jos mittari on S1-moodissa,
vastaanotin on vaihdettava, ja rtl-sdr + rtl_wmbus osaa S:n, T:n ja C:n.
**Siksi moodi kuuluu vesilaitokselle menevään kysymyslistaan** — se ratkaisee
onko koko rautavalinta oikea.

**Toinen puoli päättelystä kestää: C1 tuli katetuksi.** C1 ja T1 jakavat saman
radioasetuksen, ja C1 tunnistetaan preamble-tavusta `0x54` automaattisesti ilman
YAML-asetusta. Se 8,5 tunnin ajo 868,95:llä kuunteli siis molempia.

Kommentoidussa mittarilohkossa on tämän takia ansa: **`mode: [T1]` suodattaisi
C1-telegrammit pois.** Jätä oletus `Any`.

### Ratkaisu on todennäköisesti tämä: mittari on LoRaWAN-luennassa

**Tämä mittari on LoRaWAN-käytössä.** Se tiedetään asennuksesta eikä väylältä,
ja se selittää kaiken mitä yllä on mitattu.

W1:ssä radiot ovat **erilliset liput** — `LoRa WAN`, `wMBus T1`, `wMBus S1` —
eivät toisensa poissulkevia mutta eivät myöskään kytkeytyneitä toisiinsa. Jos
vesilaitos lukee mittarin LoRaWANilla, **sillä ei ole mitään syytä pitää
wM-Bus-radiota päällä**, ja on yksi hyvä syy pitää se pois: paristo on
mitoitettu viideksitoista vuodeksi ja jokainen ylimääräinen lähetys on siitä
pois. Se on konfiguraatio joka tuottaisi täsmälleen tämän tiedoston
mittaustulokset — toimiva vastaanotin, oikea taajuus, oikea moodi, ei mitään
kuultavaa.

**LoRaWAN ei ole vaihtoehtoinen paikallinen reitti.** Lähetykset menevät
vesilaitoksen verkkopalvelimelle, ja hyötykuorma on salattu istuntoavaimilla
joita se palvelin hallinnoi. Paikallinen LoRa-vastaanotin — komponentti tukee
SX1276:ta ja SX1262:ta, eli rauta olisi olemassa — näkisi että lähetyksiä
tulee, mutta ei niiden sisältöä. **Avaimet ovat kauempana kuin se AES-avain
jota tässä alun perin lähdettiin kysymään**, koska ne eivät ole mittarin
ominaisuus vaan verkon.

Kaksi seurausta:

- **Kysymyslistan ensimmäinen kohta vaihtuu.** Ei enää "missä moodissa se
  lähettää" vaan **"onko wM-Bus T1 päällä lainkaan, ja voitteko kytkeä sen".**
  Se on pyyntö muuttaa asetusta heidän omassa laitteessaan, ja siihen voi tulla
  kieltävä vastaus paristoperustelulla — mikä on rehellinen perustelu eikä
  pelkkä byrokratia.
- **NFC nousee ensisijaiseksi.** Se on paikallinen, ei tarvitse avainta, ei
  radiota eikä lähetysikkunaa, **eikä siihen vaikuta se kumpaa radiota
  vesilaitos käyttää.** Mittarin data on NFC-rajapinnassa riippumatta siitä
  lähettääkö se mitään.

**Yksi hypoteesi jonka tämä herätti, ja jonka pidempi aineisto kaataa.** Ne
kohinapaketit voisivat olla mittarin omia LoRaWAN-lähetyksiä, joita 2-FSK-
vastaanotin näkee roskana — LoRa on chirp-hajaspektri eikä CC1101 demoduloi
sitä, mutta chirp voi laukaista väärän sync-osuman. LoRaWAN-vesimittari
lähettää säännöllisin välein, joten hypoteesi on testattavissa aikaväleistä.

Kahdenkymmenen paketin välit 30 tunnin ajalta ovat 30, 140, 66, 88, 72, 45,
128, 92, 25, 38, 15, 103, 130, 32, 50, 9, 210, 480 ja 60 minuuttia.
Vaihteluväli on **yhdeksästä minuutista kahdeksaan tuntiin.** Vastaväite oli
että jos vastaanotin osuisi vain satunnaiseen osaan lähetyksistä, välit
olisivat silti saman perusjakson monikertoja — ja niitä ne eivät ole: yksikään
jakso tunnin sisällä ei sovi näihin edes löysästi, vaan parhaallakin ehdokkaalla
pahin poikkeama on **yli kolmannes jaksosta.**

Se on kohinaa. **Merkintä on käsitelty**, ja jäljelle jää mitä 8 tavun purskeet
ovat olleet alusta asti: vääriä sync-osumia.

### Hypoteesi 2: mittari ei lähetä silloin kun kuunnellaan

Kolme muotoa, halvimmasta alkaen:

1. **Lähetysikkuna.** Oletus ma–pe 6:00–18:00 selittää yön mittauksen
   sellaisenaan. Tarkistus: kuuntele arkena päiväsaikaan.
2. **Kuljetustila.** Uudessa mittarissa radio on pois päältä ja aktivoituu
   automaattisesti kun kumuloitunut tilavuus ylittää **10 litraa**. Sama
   tapahtuma lukitsee konfiguraatioparametrit pysyvästi. Tarkistus:
   kokonaistilavuus ei ole nolla.
3. **Radio konfiguroitu pois.** Tämä menee vesilaitokselle.

Tämä on sama muoto kuin aidonin este, ja sen ratkaisu on sama: kysy, ja kysy
ajoissa.

### Hypoteesi 3: vastaanotin ei kokoa kehystä

Tämä ei ollut listalla lainkaan, ja se on syytä pitää mielessä ennen kuin
mittarista tehdään johtopäätöksiä.

[Issue #425](https://github.com/SzczepanLeon/esphome-components/issues/425),
avattu 2.8.2026 ja yhä avoin: `wmbus_radio/CC1101 receives only noise (8-byte
packets, RX FIFO overflow) — never captures full telegrams`. Kiinnitetty commit
on `main`:n kärki, joten korjausta ei ole olemassa eikä pinnin siirtäminen auta.

Epäily kohdistuu siihen että GDO0 laukeaa FIFO-kynnyksestä eikä sync-wordin
osumasta. RF-asetukset ovat sukupolvien välillä tavu tavulta identtiset; ero on
lukustrategiassa:

| | `version_4` | `main` 5.1.7 |
|---|---|---|
| FIFO-kynnys RX:n alussa | **4 tavua** | **32 tavua** |
| GDO2 sync-porttina | kyllä, oma tila | ei käytössä |
| PKTLEN pituuden selvittyä | vaihdetaan fixed-tilaan | jää infinite-tilaan |
| `sync_mode`-asetus | on | ei ole |

**Oireprofiili ei silti täsmää tähän laitteeseen**, ja se erotus kannattaa
säilyttää:

| | #425 | tämä laite |
|---|---|---|
| Raportoijia | 1 | |
| Kohinapaketteja | 1–3 s välein | 1 / 11 min |
| `RX FIFO overflow` | jatkuvasti | **ei yhtään** |
| CPU:n näännyttäminen | kyllä | ei havaittu |

Sama 8 tavun allekirjoitus, eri intensiteetti. Se on varteenotettava epäilty eikä
kirjattu syy.

### Täysi lähetysikkuna mitattu: nolla kehystä

7.9.2026, maanantai, 868,95 MHz, mittari parin metrin päässä. **Ensimmäinen
mittaus tässä projektissa jonka voi kirjata sellaisenaan** — kolme aiempaa
kumoutui, koska ne mittasivat jotain muuta kuin väittivät.

| | |
|---|---|
| Kuunneltu ikkunan sisällä | noin **7,5 h** (10:13 → 18:00, kaksi flashausta välissä) |
| Kohinapaketteja | **6** — 10:11, 11:18, 12:46, 13:58, 14:42, 16:50 |
| Kokonaisia kehyksiä | **0** |
| `RX timeout` / `RX FIFO overflow` | **0** |
| FIFO-kynnys 32 vs. 4 tavua | ei eroa |

Odotusarvo jos mittari lähettäisi 16 sekunnin välein: **noin 1700
vastaanottoa.** Yön mittauksen kanssa yhteensä noin 16 tuntia ja nolla kehystä.

Neljä muuttujaa olivat tällä kertaa oikein samaan aikaan — oikea taajuus, moodi
jota komponentti tukee, lähetysikkunan sisällä, ja vastaanotin todistetusti
elossa. **Vastaanottimen puoli on siis niin pitkälle todistettu kuin ilman
kehystä voi**, ja se on syy pitää mittarin puolta ensisijaisena.

Yksi kirjanpitohuomio: `LOCAL PATCH` -rivi ei ole kaappauslokissa vaan
flashauksen boottitulosteessa. Kokoonpanotuloste toistuu vain **uudelle**
liittyvälle lokiasiakkaalle, ja taustalla `>>`-ohjauksella pyörinyt virta oli jo
kiinni — sama mekanismi joka on kirjattu juuren CLAUDE.md:hen.

#### Ja 20 tuntia perään valvomatta: sama nolla

Kaappaus jäi päälle ikkunan päätyttyä ja katkesi vasta 8.9.2026 klo 14:00
sähkökatkoon. Se antoi ilmaiseksi sen mitä ikkunamittaus ei kata: illan, yön ja
seuraavan arkiaamun puolelta päivään.

| | |
|---|---|
| Lisäaikaa ikkunan jälkeen | noin **20 h** (7.9. 18:00 → 8.9. 14:00) |
| Uusia kohinapaketteja | **12** — koko lokissa yhteensä 20 |
| Kokonaisia kehyksiä | **0** |
| Uudelleenkäynnistyksiä | **0** |

Kumulatiivisesti kuuntelua on siis noin **36 tuntia ja nolla kehystä.**

Ajo on samalla vahvin todiste vastaanottimen vakaudesta mitä tässä on: `Uptime`
juoksi katkeamatta **95 584 sekuntiin eli 26,5 tuntiin** viimeisestä
flashauksesta 7.9. klo 11:28. Levy ei siis kaatunut, jumittunut eikä pudonnut
verkosta kertaakaan sinä aikana kun se ei kuullut mitään — ja `Uptime` on ainoa
rivi joka erottaa nämä toisistaan, kuten juuren CLAUDE.md:hen on kirjattu.

**Tämä ei ollut suunniteltu mittaus vaan päälle unohtunut loki.** Uutta se ei
kumoa — ikkunamittaus kaatoi lähetysikkunahypoteesin jo — mutta se poistaa
viimeisenkin epäilyn ajoituksesta: ikkunan sisä- ja ulkopuoli on nyt mitattu
peräkkäin katkeamatta, eikä kummallakaan puolella ole eroa.

### Testi: FIFO-kynnys 32 → 4 tavua

Tehty paikallisessa työkopiossa, koska yhtä tavua ei voi muuttaa etälähteeseen.
Puu on ladattu samasta commitista kuin YAMLin kiinnitys, ja **ero on tämä yksi
rivi** tiedostossa `wmbus_radio/transceiver_cc1101.cpp`:

```c
// this->write_register(CC1101_FIFOTHR, 0x07);   // upstream: RX FIFO >= 32 tavua
   this->write_register(CC1101_FIFOTHR, 0x00);   // version_4: RX FIFO >= 4 tavua
```

`upstream/` on gitignoressa eikä kolmannen osapuolen koodi mene tähän repoon,
joten **muutos on kirjattu tänne jotta se on toistettavissa ilman sitä puuta.**
YAMLissa `external_components` osoittaa toistaiseksi paikalliseen polkuun ja
GitHub-lähde on kommentoituna sen alla.

**Kontrolli on toinen paikallinen lisäys, ei pakettitahti.** Rivi `configuring
FIFO threshold` on VV-tasolla ja siis setup-vaiheessa, jota API-lokivirta ei näe,
eikä tagin tasoa voi nostaa globaalin yli — ylemmät tasot on käännetty pois.
Siksi `transceiver.cpp`:n `dump_config`:iin on lisätty rivi:

```
[C][wmbus.transceiver]:   LOCAL PATCH: FIFOTHR=0x00 (RX FIFO >= 4 bytes)
```

`ESP_LOGCONFIG` on C-tasolla ja **kokoonpanotuloste toistuu joka lokiasiakkaan
liittyessä**, joten patchatun puun voi todeta binäärissä milloin tahansa ilman
sarjaporttia. Jos rivi puuttuu, käännös ei käyttänyt tätä puuta.

**Ja se ansaitsi itsensä heti.** Ensimmäinen käännös paikallisen puun kanssa
tuotti kokoonpanotulosteen ilman tätä riviä: `podman cp` oli pesinyt puun
`/config/upstream/upstream`:iin, koska kohdehakemisto oli jo olemassa, ja
käännös luki vanhaa kopiota. Ilman merkkiriviä se olisi näyttänyt onnistuneelta
testiltä. **Kopioi sisältö eikä hakemistoa:** `podman cp <polku>/upstream/.
esphome:/config/upstream/`.

**Pakettitahti ei kelpaa kontrolliksi, ja se oli tässä ensin väärin.**
`MDMCFG2 = 0x06` vaatii 16/16-bitin sync-osuman ennen kuin FIFO alkaa täyttyä,
eli kohinapakettien tahti syntyy väärien sync-osumien todennäköisyydestä.
FIFO-kynnys päättää vain siitä toimitetaanko osuman jälkeinen purske jos se ei
kasva 32 tavuun. Vaikutus on siis kohtalainen eikä dramaattinen, ja mitattu ero
— yksi paketti 65 minuutissa vastaan noin yksi kahdessa tunnissa — sopii yhtä
hyvin kumpaan tahansa johtopäätökseen.

| Havainto | Tulkinta |
|---|---|
| `LOCAL PATCH` -rivi lokissa | Patch on binäärissä. Vasta tämän jälkeen hiljaisuus tarkoittaa jotain |
| Rivi puuttuu | Käännös ei käyttänyt paikallista puuta — `esphome clean` ja uudelleen |
| Kokonainen kehys | Hypoteesi 3 vahvistuu ja este oli vastaanottimessa |

Kolmas rivi on se jota testi hakee. Kaksi ensimmäistä ovat kontrolli, ja se on
tässä tarpeen: **kaksi kertaa aiemmin on tulkittu mittausta joka ei mitannut
sitä mitä luultiin** — S-moodi väärillä rekistereillä ja 8 tavun otsikot jotka
eivät olleet otsikoita.

Jos senkin jälkeen on hiljaista, `version_4` on todistetusti toimiva CC1101-
toteutus, mutta kahdella ehdolla: **GDO2 on kytkettävä takaisin** sync-portiksi
ja **ei GPIO2:een** (strapping, perusteltu yllä), ja #425:n raportoija sanoo
`version_4`:n kaatuvan nykyisillä ESPHome-versioilla. Siksi se on vasta viimeinen.

# AES-128 salaus

Axioma Qalcosonic W1 käyttää yleensä AES-128-salausta.

AES-avain EI löydy:

- näytöstä
- tyyppikilvestä
- sarjanumerosta

Sen saa yleensä:

- vesilaitokselta
- isännöitsijältä
- rakennuttajalta
- mittarin toimittajalta

Ilman AES-avainta voidaan yleensä nähdä vain salatut telegrammit.

# Mittarin oma konfiguraatio on luettavissa NFC:llä

W1:ssä on NFC-rajapinta, ja **konfiguraation lukeminen ei vaadi salasanaa** —
vasta kirjoitus vaatii. Puhelimella saa siis suoraan mittarista ne asiat joita
tässä tiedostossa on arvailtu yleisistä lähteistä:

- radiotila päällä vai pois
- `wMBus T1` ja `wMBus S1` erillisinä lippuina — eli **moodi**
- lähetysikkunan viikonpäivä- ja kuukausimaski
- kokonaistilavuus, eli onko kuljetustila jo purkautunut

Tämä olisi halvin tapa tarkistaa lähetysikkunaoletus, ja se on **sama sääntö kuin
muualla tässä tiedostossa: laitteen oma sanoma voittaa taulukon.**

**Käytännössä reitti on kiinni**, ja se johtuu sovelluksista eikä mittarista:

| Sovellus | |
|---|---|
| `Qalcosonic configurator W1`, `QW1 Radio Activator` | luki ilman salasanaa ja näytti aikataulumaskit — **poistettu Play Storesta**, enää APK-peileissä |
| **Axilink** | Axioman nykyinen, NFC ja optinen pää — **salasanasuojattu**, tunnus tulee jälleenmyyjältä |
| **Axilink Lite** | ilmainen ja virallinen, kertoisi onko mittari aktiivinen ja lähettääkö se — **ei asennettavissa Pixel 9:ään** |

Se salasanaton luku johon tässä aiemmin nojattiin **koski poistettua
sovellusta**, ei nykyistä. Reitti on siis olemassa mutta ei ilmainen: se vaatii
joko jälleenmyyjän tunnuksen, APK:n kolmannen osapuolen peilistä, tai
maahantuojan (Effectio Oy) apua.

### Ja puhelin ei näe mittaria — se on puhelimesta, ei mittarista

Napautus tuotti **ei mitään**: puhelin ei havainnut tunnistetta lainkaan. Se ei
ole havainto mittarista, ja kaksi syytä selittävät sen puhelimen puolelta.

**Mittarin NFC on ISO 15693 eli NFC-V**, ei se NFC-A jota puhelimet käyttävät
maksamiseen ja tarroihin. Tämä on päätelty luotettavasti mutta epäsuorasti:
`esphome_qalcosonicnfc` lukee W1:tä **PN5180-piirillä**, joka on nimenomaan
ISO 15693 -lukija.

**Androidilla NFC-V on rajoitettu.** Käyttöjärjestelmä tarjoaa siihen vain
raakaa `transceive`-liikennettä ilman NDEF-tukea, ja **Android 15 lisäsi
tunnisteiden lupajärjestelmän jossa ISO 15693 on "restricted" ellei jokin
sovellus ole erikseen sallittujen listalla**; Android 16 lisäsi siihen
vahvistusdialogin. Ilman NFC-V-kelpoista sovellusta järjestelmä ei reititä
tunnistetta minnekään, eli **paljas puhelin on hiljaa vaikka tunniste olisi
kentässä.** Se selittää todennäköisesti myös sen miksi Axilink Lite ei
asentunut kyseiseen puhelimeen.

Toinen syy on kohdistus. Mittarin kela on tarkassa paikassa — paikannettu
FCC-hakemuksesta — ja siihen on tehty **3D-tulostettu kotelo joka kohdistaa
PN5180:n antennin.** Jos kohdistus vaatii tulostetun kotelon, se ei ole
armollinen puhelimen kelalle.

**Sääntö tästä: puhelimen hiljaisuus ei kuulu mittarin vikaluetteloon.** Se on
sama virhemuoto kuin S-moodin testi väärillä rekistereillä — mittaus joka ei
mittaa sitä mitä sen otsikko sanoo.

### Siksi PN5180 ei ole enää varavaihtoehto

[esphome_qalcosonicnfc](https://github.com/dbmaxpayne/esphome_qalcosonicnfc) on
noin viiden euron moduuli, ja se **ohittaa kolme estettä kerralla**: ei
AES-avainta, ei lähetysikkunaa, eikä väliä sillä kumpaa radiota vesilaitos
käyttää. Sille on valmis kotelomalli antennin kohdistukseen.

Hinta on rehellisesti sanottava, ja se kaataa yhden tämän tiedoston omista
perusteluista: **vastaanotin on vietävä mittarin viereen.** Tässä on luettu
että wM-Bus on radio ja siksi paikan valitsee itse sieltä missä WiFi kuuluu —
NFC:llä se vapaus katoaa, ja mittarikaivo tai tekninen tila on se paikka jossa
WiFin pitää silloin kuulua.

Se on eri projekti eikä korjaus tähän. Mutta kun tähän on nyt käytetty
kolmekymmentäkuusi tuntia kuuntelua nollalla kehyksellä, se on **suorempi tie
kuin radio jonka lähettämisestä ei ole todistetta.**

#### Lukijaa ostettaessa: piirin nimi on ainoa asia joka ratkaisee

**Lukijan on tuettava ISO 15693:a, ja `PN5180` on käytännössä ainoa halpa piiri
joka tukee.** Muut samaan pystyvät — RC663, ST25R3911B, TRF7970A, CR95HF — eivät
ole hyllytavaraa.

**RC522 ei kelpaa.** MFRC522 tukee vain ISO 14443A:ta eli MIFARE-kortteja. Se on
sama 13,56 MHz, sama SPI, sama 3,3 V ja usein sama myyntikuvaus — **ja se on eri
protokolla.** Sama muoto kuin stiebelissä kirjattu opetus siitä ettei
RS-485-moduuli kelpaa CAN-väylälle: yhteinen fysiikka ei ole yhteensopivuus.

**Ratkaisevat merkit ovat nastarimassa, eivät kotelon muodossa:**

- **`5V` ja `BUSY` rimassa.** RC522 on pelkkää 3,3 volttia eikä siinä ole
  valmiuslinjaa; PN5180 ei toimi ilman kumpaakaan. Tämä on nopein ja varmin
  tarkistus, ja sen voi tehdä tuotekuvasta jos silkkipainatus näkyy.
- **Nastojen määrä.** MFRC522 tuo ulos kahdeksan. PN5180 tarvitsee vähintään
  yhdeksän ja levyt katkaisevat 10–16.
- **Piirin merkintä**, `PN5180` tai `PN5180A0HN`. Jos listauksessa lukee vain
  "13.56 MHz SPI, compatible with Arduino" ilman piirin nimeä, se on RC522.
- Hinta 2–3 € kappale ja myyntierä 3–5 kappaletta on RC522:n hinnoittelu;
  PN5180 on 8–10 € kappale.

### Antennin muoto ei kelpaa tunnistimeksi, ja tässä luki että kelpaa

Tässä oli neljäs merkki: *"antenni on pieni neliö samalla levyllä — PN5180 on
kaksiosainen"*. **Se on väärin ja se olisi hylännyt oikean levyn.**

Saapunut moduuli on yksiosainen **`PN5180-NFC` rev `R1.1-170710`, 70 × 39 mm**:
yksi sininen levy, jonka oikeassa päässä on kierukka-antenni ja vasemmassa
piiri `PN5180A0`, passiivit ja kolmentoista nastan rima `JP1`. Rimassa on sekä
`+5V` että `BUSY`, eli molemmat ne joita RC522:ssa ei ole.

Kaksiosaisuus on siis **yhden myydyimmän mallin ominaisuus eikä piirin
ominaisuus**, ja se oli tässä tiedostossa yleistetty tunnistimeksi yhden
tuotekuvan perusteella.

Se on sama virhe jota tämän listan oma kärki varoittaa tekemästä — yhteinen
fysiikka ei ole yhteensopivuus — vain toisin päin: **yhteinen ulkonäkö ei ole
yhteensopimattomuus.** Tunnistin on piirin nimi ja sähköinen vaatimus, ei
muoto.

Hae siis piirin nimellä `PN5180`, ei kuvauksella. Ja tarkista rimasta että
siinä on **sekä 5 V että 3,3 V** — lähetinpää tarvitsee viisi volttia, logiikka
kolme.

**Asetusten muuttaminen ei onnistu**, ja syy on rakenteellinen: parametrien
kirjoitus lukittuu pysyvästi kun mittari on läpäissyt 10 litran kynnyksen.
Asennetun mittarin aikataulua ei siis säädetä kuluttajan työkaluilla — se on
vesilaitoksen tai valmistajan oikeus.

**Mittarissa on kommunikointikredit**: lisärajapintojen käyttö on rajattu noin
20 minuuttiin kuukaudessa pariston säästämiseksi, ja rajan täyttyessä rajapinta
lukkiutuu tunnin vaihtumiseen asti. Älä siis pollaa NFC:tä.

Näyttö on tätä heikompi todiste. LCD:llä on radioviestinnän indikaattori, mutta
**ei ole varmistettu kertooko se "radio konfiguroitu päälle" vai "lähetys
käynnissä"**, ja yksittäisiä näyttösivuja voi piilottaa asennuksessa — sivun
puuttuminen ei siis todista mitään.

## Pollausväli johdetaan kreditistä, ei tottumuksesta

PN5180 on saapunut, ja tarkoitus on pollata. Se käy — mutta väli on laskettava
mittarin kommunikointikreditistä eikä valittava sen mukaan mikä tuntuu
normaalilta.

```
20 min/kk  =  1200 s/kk  =  40 s/vrk
```

**Kaikki riippuu yhden luvun kestosta, eikä sitä tiedetä.** Kahden sekunnin
oletuksella:

| Väli | Lukuja/vrk | Kulutus | |
|---|---|---|---|
| 1 h | 24 | 24 min/kk | **yli budjetin** |
| 2 h | 12 | 12 min/kk | mahtuu |
| 3 h | 8 | 8 min/kk | väljä |

Viiden sekunnin luvulla sama taulukko siirtyy kokonaan: kaksi tuntia on jo
30 min/kk. **Mittaa yhden luvun kesto ja johda väli siitä kertoimella 2–3.**
Se on yksi mittaus ja se poistaa koko arvailun.

**Aloita kolmesta tunnista.** Vesi on kumulatiivista ja HA:n pitkän aikavälin
tilastot lasketaan tunneittain, joten kolmen tunnin väli ei menetä niille
mitään. Ainoa tiheämpää haluava on vuotovahti, ja juokseva vessa jää kiinni
saman päivän aikana kahdeksalla lukemalla. Väljästä välistä jää kaksi
kolmasosaa budjettia sille että kestoarvio on pielessä.

### Vikatila on hiljaisuus, joten budjetti rakennetaan näkyväksi

Rajan täyttyessä rajapinta **lukkiutuu tunnin vaihtumiseen asti**. Se ei
palauta virhettä joka näkyisi entiteetissä — luku vain epäonnistuu ja vanha
arvo jää paikalleen näyttämään tuoreelta.

Se on sama vikaluokka joka on tässä repossa korjattu viidesti yhden viikon
aikana: **vahdin hiljaisuus ja vahdin sokeus näyttävät samalta.** Siksi tämä
kuuluu rakentaa sisään alusta asti eikä jälkikäteen:

- **laske luvut** ja julkaise arvio kuluneesta kreditistä omana entiteettinään
- **havaitse epäonnistunut luku** ja perääntele sen sijaan että yrittäisit
  heti uudelleen — uusintayritys kuluttaa samaa budjettia joka juuri loppui
- **päästä entiteetti tuntemattomaksi** jos luku ei ole onnistunut kolmeen
  väliin, ettei vanha lukema teeskentele tuoretta

### Suora rima pinoaa levyt, se ei nosta C3:a pystyyn

Tässä luki hetken että suoraan `JP1`:een juotettu C3 **seisoo kohtisuorassa**
ja työntyy parikymmentä milliä irti pinnasta, ja että vaakatasoon pääsemiseksi
nastat pitäisi taivuttaa. **Se on väärin päin.**

Suora nastarima menee molempien levyjen reikien läpi ja pitää ne
**yhdensuuntaisina** — niin kaikki lisäkortit kiinnittyvät. Kulmarima on se
joka kääntää liitoksen levyn tasoon ja vie toisen levyn viereen.

Oikea kokoonpano on siis pino:

```
C3            1,2 mm
rima          korkeus valittavissa
PN5180        1,6 mm
------------  mittari
```

Noin yksitoista milliä vakiorimalla, ja **C3 peittää vasemman kolmanneksen**
eli sen missä piirit muutenkin ovat. Antennialue jää kokonaan vapaaksi: C3:n
sisäreuna yltää ~21 mm:iin ja kela alkaa ~30 mm:stä.

**Riman korkeus on suunnitteluparametri eikä jäännös.** C3:n maataso leijuu
antennin sovituspiirin `L1`/`L2` yllä, ja mitä matalampi rima, sitä lähempänä.
Vakiorima jättää noin kuusi milliä ilmaa — älä paina C3:a kiinni pintaan
vaikka se mahtuisi.

### Oma solmu C3:lla, radiosolmuun ei kosketa

**NFC rakennetaan erilliselle ESP32-C3 SuperMinille** eikä nykyisen
`esp32dev`-solmun päälle. Perustelu on järjestys eikä rauta: radion tila on yhä
avoin kysymys, ja **NFC-luku on se joka vastaa siihen.** Jos radiosolmua
puretaan ennen lukua, kysymys sulkeutuu pysyvästi; jos se jätetään rauhaan,
molemmat ovat pystyssä silloin kun vastaus tulee. DevKit puretaan vasta sen
jälkeen — tai ei pureta, jos radio osoittautuukin päälle kytketyksi.

Levyn vaihto on myös halvempaa nyt kuin juotosten jälkeen, ja hyllyllä on kuusi
C3:a.

**Antenniperustelu tarkistettiin ja se kaatui.** Tässä luki hetken että
mittarin luona WiFi on talon huonoin, koska NFC pakottaa vastaanottimen
mittarin viereen. Omistaja korjasi: mittari on samassa tilassa 1-Wire-solmun
kanssa. Mittaus vahvistaa sen riittäväksi:

| Solmu | WiFi |
|---|---|
| onewire, samassa tilassa | **−70 dBm** (vaihtelu −69…−76) |
| stiebel | −77 dBm |
| axioma työpöydällä | −56 dBm |

−70 ei ole talon paras, mutta se on **todistetusti riittävä**, ja todiste on
vahvempi kuin lukema: siinä tilassa on jo C3, se on ottanut useita
OTA-päivityksiä ja streamannut lokia vuorokausia katkeamatta. Sama levytyyppi,
sama huone.

**Siksi hirviradan WROOM-32U jää hirviradalle.** Sen ulkoantenniperustelu
lepää kipinöivässä harjamoottorissa suljetussa rasiassa, eikä tämä projekti
tarvitse sitä.

### Kohdistus ilman tulostettua koteloa

Upstream-projektissa on 3D-tulostettu kotelo joka kohdistaa antennin mittarin
kelaan. **Sitä ei käytetä**, ja syy on parempi kuin maku: kotelo lukitsee
asennon ennen kuin se on todennettu. Levyssä on neljä kiinnitysreikää, ja
nippuside tai ohut kaksipuolinen teippi antaa säätää kohdistusta ensimmäisen
onnistuneen luvun jälkeen — kotelo ei anna.

**Asento seuraa fysiikasta eikä ole makuasia:**

- **Litteänä pintaa vasten.** NFC on induktiivista kytkentää: kenttä kulkee
  kelan tason läpi, joten levy ei mene kyljelleen. Kierto tasossa ei merkitse
  mitään, koska molemmat ovat silmukoita eivätkä dipoleja.
- **Antennipää kelan päälle, rimapää poispäin.** Levystä vain oikea ~40 mm on
  antennia, ja kun rima osoittaa poispäin, johdot lähtevät sivuun eivätkä
  taitu kelan yli.
- **Sileä puoli mittariin päin.** Komponentit nostavat levyä millimetrejä irti
  ja kytkentä heikkenee etäisyyden myötä nopeasti.
- **Ei metallia väliin eikä antennin taakse.** Johtava pinta vaimentaa kentän
  ja virittää antennin pois. Nippuside on muovia; kannake ei välttämättä ole.
- **Tuenta antennipäästä, ei rimapäästä.** Ks. seuraava luku: levy saa jäädä
  vasemmasta päästä irti, mutta kelan pää ei.

### Sileysvaatimus koskee antennialuetta, ei koko alapintaa

Tässä luki ensin ehdottomasti *"älä juota sileälle puolelle"*, ja se on liian
tiukka. Oikea sääntö on kapeampi ja seuraa siitä mitä kytkentä oikeasti vaatii:

> **Antennin kohdalla alapinnan on oltava sileä. Muualla ei ole väliä.**

Kela on levyn oikea ~40 mm. Vasen kolmannes on yli 30 mm siitä, ja sinne tuleva
juotosnysty **ei nosta antennia vaan kallistaa levyä** — puoli milliä
neljänkymmenen millin matkalla on alle asteen.

**Mutta se pätee vain jos levy tukeutuu antennipäästä.** Jos kiinnitys painaa
vasemmasta päästä, kallistus kääntyy toisin päin ja nostaa kelan irti
mittarista — eli tuottaa täsmälleen sen vian jota vältetään. Nippuside tai
teippi menee siis **antennin puolelle**, ja vasen pää saa jäädä irti.

Tästä seuraa käytännön etu: **PN5180:n pintapuolelle ei tarvitse koskea
kolvilla kertaakaan.** Rima työnnetään reikiin ylhäältä mutta juotetaan
altapäin — läpiladonnan normaali tapa — ja hyppylangat juotetaan altapäin
samoin. Kaikki yhdeksän liitosta tehdään yhdeltä puolelta, ja ne mahtuvat
vasempaan kolmannekseen.

### Yhdeksän liitosta, kahdeksantoista juotosta

Liitoksia on yhdeksän ja jokaisella on kaksi päätä: toinen PN5180:ssa, toinen
C3:ssa. "C3:n omia liitoksia" ei ole olemassa — reitti vain on eri.

| | Reitti | PN5180:n pää | C3:n pää |
|---|---|---|---|
| `RST` `NSS` `MOSI` `BUSY` | rimanasta | alapuolelta | C3:n padiin |
| `MISO` `SCK` `+5V` `3.3V` `GND` | lakkalanka 0,2–0,3 mm | alapuolelta | C3:n padiin |

**Kokoonpanojärjestys on pakotettu**, koska C3:n alle ei pääse kolvilla sen
jälkeen kun se on paikallaan:

1. Viisi lakkalankaa alapuolelta, vasempaan kolmannekseen
2. Rima neljään padiin, juotos alapuolelta — teippaa rima kiinni ennen kääntöä
3. C3 rimaan ylhäältä, lankojen toiset päät sen kauempaan riviin
4. Vetokevennys liimalla tai nippusiteellä

Langat ennen rimaa siksi että riman nastat törröttävät alapuolella juuri siinä
missä ohuita lankoja pitäisi reitittää.

### Etsi kela katsomalla, älä pollaamalla — mutta käsin kokeilu on halpaa

Tässä luki hetken että paikkaa ei saa etsiä kokeilemalla lainkaan. **Se oli
liian jyrkkä.** Ero on automaattisen ja käsin tehdyn välillä:

| | Krediittiä 1200 s/kk:sta |
|---|---|
| Kymmenen käsin tehtyä koelukua | ~20–30 s, alle 3 % |
| Pollausluuppi joka hakee osumaa | kuukausi minuuteissa |

Kokeileminen ei siis ole se mikä budjetin polttaa, vaan **silmukka joka jää
päälle etsimisen ajaksi.** Kytke automaattipollaus päälle vasta kun kohdistus
on löytynyt ja levy on kiinni pysyvästi.

Halvin järjestys:

1. **Paikanna kela katsomalla** — nolla krediittiä. Kannessa on usein merkintä
   tai muotoiltu ympyrä; kela on tyypillisesti näytön lähellä muovin takana; ja
   **W1:n FCC-hakemuksen sisäkuvat** ovat julkisia ja näyttävät sen suoraan. Se
   on sama lähde josta upstream-tekijä sen paikansi.
2. **Kiinnitä löysästi ja lue kerran.**
3. **Jos ei osu, siirrä senttimetri.**

Vasta kun luku onnistuu, kiinnitys tehdään pysyväksi ja pollaus kytketään
päälle.

### Kytkentä

Piirretty [`nfc-wiring.svg`](nfc-wiring.svg):ssä.

**Valittu asento on A: USB-C ylöspäin, UART vapaana.**

| JP1 | C3 | Reitti |
|---|---|---|
| `RST` | `GPIO5` | rimanasta |
| `NSS` | `GPIO6` | rimanasta |
| `MOSI` | `GPIO7` | rimanasta |
| `BUSY` | `GPIO10` | rimanasta |
| `MISO` | `GPIO3` | lakkalanka |
| `SCK` | `GPIO4` | lakkalanka |
| `+5V` | `5V` | lakkalanka |
| `3.3V` | `3V3` | lakkalanka |
| `GND` | `GND` | lakkalanka |

**Rimasta vedetään irti neljä nastaa** ennen asennusta: `GPIO8` ja `GPIO9` ovat
strapping, `GPIO20` osuisi maahan ja `GPIO21` käyttämättömään padiin.

Käytetyt nastat ovat `3, 4, 5, 6, 7, 10` — sama turvallinen kuusikko kuin
alusta asti, vain eri signaaleille. Strapping `2, 8, 9`, USB `18/19` ja UART0
`20/21` jäävät kaikki vapaiksi.

**Hylätty vaihtoehto B** olisi kääntänyt C3:n niin että USB-C osoittaa
käyttämättömien padien suuntaan. Se maksaisi UART0:n, koska kääntö peilaa
kaikki kahdeksan nastaa ja `GPIO20`/`GPIO21` päätyisivät `RST`:ksi ja
`NSS`:ksi. USB CDC riittää lokiin, mutta sarjakonsoli on halvempi pitää kuin
saada takaisin.

**A:n hinta on että USB-C jää `+5V`- ja `3.3V`-padien yläpuolelle.**
Asennuksessa se ei haittaa, koska langat juotetaan ennen C3:a — mutta niiden
korjaaminen vaatii C3:n irrottamisen. Tee ne huolella kerralla.

### Vain SCK osuu silkkipainatukseen

C3:n silkki sanoo `GPIO5=MISO`, `GPIO6=MOSI`, `GPIO7=SS`. Tässä ne ovat `RST`,
`NSS` ja `MOSI`. Ainoa osuma on `GPIO4=SCK`.

Se on toiminnallisesti yhdentekevää — C3 reitittää SPI:n GPIO-matriisin läpi ja
ESPHome ottaa nastat konfiguraatiosta — mutta **kirjoita kartta levyn kylkeen
tussilla.** Kolmen kuukauden päästä silkki valehtelee kahdeksalla nastalla
yhdeksästä.



Neljä kohtaa jotka menevät helposti väärin:

- **Molemmat jännitteet.** Lähetinpää ottaa 5 V ja piikittää satoja
  milliampeereja RF-purskeessa; logiikka on 3,3 V. 100 µF moduulin viereen —
  ja **tarkista että SuperMinissa on 5V-nasta**, kaikissa kloonoissa ei ole.
- **BUSY on pakollinen.** PN5180 ei ole tavallinen SPI-orja: jokaisen komennon
  jälkeen on odotettava BUSY:n laskua. Ilman sitä luku palauttaa roskaa eikä
  virhettä — taas vika joka ei näytä vialta.
- **Koko moduuli menee mittaria vasten, ja C3 sen viereen.** Saapunut levy on
  yksiosainen, joten antennia ei voi sijoittaa erilleen logiikasta. SPI on
  nopea väylä eikä siedä pitkiä johtoja, joten C3:n on oltava 10–20 cm:n
  päässä — eli sekin päätyy mittarin luo. Se ei ole ongelma tässä tilassa,
  mutta se poistaa sen joustavuuden jonka kaksiosainen malli olisi antanut.
- **Lukuetäisyys on lyhyempi kuin kaksiosaisella.** Integroitu kierukka on
  pienempi kuin erillinen luottokortin kokoinen antennilevy, joten kohdistus
  mittarin omaan kelaan on tarkempaa työtä. Varaa siihen aikaa ensimmäisellä
  kerralla.
- **Tarkista komponentin alustatuki ennen kuin harkitset D1 miniä.** ESP8266:lla
  SPI:n jälkeen jää kolme turvallista nastaa, mikä riittää täpärästi — mutta
  `esphome_qalcosonicnfc`:n ESP8266-tuki on todentamatta, eikä sitä kannata
  olettaa.

## NFC on myös vaihtoehtoinen reitti koko projektille

[esphome_qalcosonicnfc](https://github.com/dbmaxpayne/esphome_qalcosonicnfc)
lukee W1:n NFC:llä PN5180-moduulilla ja tuo ESPHomeen kulutuksen, virtaaman,
lämpötilat, paristotason ja virheliput. **Se ei tarvitse AES-avainta eikä
lähetysikkunaa** — eli se ohittaa kerralla molemmat tämän projektin esteet.

Hinta on uusi moduuli ja se että vastaanotin on vietävä mittarin viereen, mikä
kaataa tämän tiedoston oman perustelun siitä että wM-Bus antaa valita paikan
vapaasti. Se on siis eri projekti eikä korjaus tähän, mutta se on olemassa jos
avain ei koskaan tule.

---

# Varsinainen ESPHome-konfiguraatio

> **Tämä lohko on väärin kahdella tavalla ja säilytetään varoituksena.** Se on
> `version_4`:n skeema, ja sen `type: axioma` ei ole olemassa ajurina lainkaan —
> oikea on `q400`. Kenttien nimet `water_m3` ja `flow_m3h` ovat samasta
> keksityn tuntuisesta perheestä eikä niitä ole nähty missään tulosteessa.
>
> Ajettava muoto on [`axioma.effection.yaml`](axioma.effection.yaml):ssa
> kommentoituna ja odottaa Meter ID:tä ja avainta.

```yaml
sensor:
  - platform: wmbus
    meter_id: 12345678
    type: axioma

    water_m3:
      name: "Vesimittari"

    flow_m3h:
      name: "Virtaus"

    temperature_c:
      name: "Veden lämpötila"
```

---

# GitHub-projektit

## ESPHome Wireless M-Bus komponentti

https://github.com/SzczepanLeon/esphome-components

### Versiot ovat kaksi sukupolvea, ja tämä projekti sekoitti ne

Tarkistettu lähteestä 6.9.2026. Kaksi yhteensopimatonta skeemaa on yhtä aikaa
elossa, ja haaran nimi ei kerro kumpi on kumpi:

| | Viimeisin | Skeema |
|---|---|---|
| `version_4` | 4.1.4, helmikuu 2025 | yksi `wmbus:`-lohko, `gdo0_pin` + `gdo2_pin`, `sensor: - platform: wmbus` |
| **5.x** | **5.1.6, elokuu 2025** | `spi:` + `wmbus_radio:` + `wmbus_meter:`, `irq_pin`, anturit omalla alustallaan |

5.0.0:n julkaisuteksti on `Full refactor/rewrite by Kuba`, mikä selittää miksi
mikään ei siirry sellaisenaan.

**YAML oli kiinnitetty `@version_4`:ään ja kirjoitti 5.x:n skeemaa.** Se ei
olisi kääntynyt: `wmbus_radio` ei ole olemassa nelosessa. Virhe ei ollut
skeeman valinnassa vaan siinä että versio kiinnitettiin lukematta mitä siihen
kuuluu — ja tiedoston oma kommentti kehui kiinnittämistä samalla rivillä.

**Korjaukseksi valittiin julkaisutagi `@5.1.6`, ja se oli väärin sekin.**
Validointi kaatoi sen heti:

```
Unknown value 'CC1101', valid options are 'SX1276'.
'reset_pin' is a required option for [wmbus_radio].
[frequency] is an invalid option for [wmbus_radio].
```

**Viiden sarja ei tunne CC1101:tä.** Uudelleenkirjoitus lähti liikkeelle
SX1276:sta, ja CC1101 tuli takaisin vasta sen jälkeen — päähaaraan, jota ei ole
koskaan julkaistu. Yhtään julkaisua jossa olisi sekä CC1101 että nykyskeema ei
siis ole olemassa:

| | CC1101 | Nykyskeema |
|---|---|---|
| `version_4` 4.1.4, 2/2025 | kyllä | ei |
| `5.1.6`, 8/2025 | **ei** | kyllä |
| `main` | kyllä | kyllä |

**Kiinnitys on siksi commit-tunniste**,
`7eae51c8fcefe854623b029b27bbe42e11c103ea`, päähaaran kärki 20.8.2026. Se on
ainoa muoto joka antaa molemmat: haara liikkuu, tagissa ei ole CC1101:tä,
commit ei voi muuttua. Vaihtokauppana koodi on julkaisematonta — se on
tietoinen valinta, ja vaihtoehto olisi `version_4`:n 19 kuukautta vanha
julkaisu vanhalla skeemalla.

`refresh: never` kuuluu tähän: kiinteälle commitille ei ole mitään
päivitettävää.

### Kolme kierrosta, ja opetus on lähdekritiikki

Tämä ratkesi vasta kolmannella yrityksellä, ja joka kierros kaatui samaan
asiaan: **README:hen luotettiin lähteenä.**

| | Uskottiin | Todellisuus |
|---|---|---|
| 1 | `@version_4` + uusi skeema | eri sukupolvet, `wmbus_radio` ei ole nelosessa |
| 2 | `components: [wmbus_radio, wmbus_meter]` | `wmbus_common` on riippuvuus jota ei mainita |
| 3 | `@5.1.6` osaa CC1101:n koska README sanoo | README on päähaaran, tagi ei ole |

Kolmas on niistä ikävin: päähaaran README kuvaa päähaaran koodia, ja se luettiin
todisteena tagista. **Dokumentaatio kuvaa aina sitä haaraa jossa se on.**

Ratkaisu tuli `wmbus_radio/__init__.py`:stä: radiotyypit löydetään
`transceiver_*.cpp`-tiedostoista, `reset_pin` on valinnainen ja `frequency` on
CC1101:n oma. Lähdekoodi kertoi sekunnissa sen mitä kolme README-lukemaa ei.

Sama kuvio kuin stiebelin `0x8000`-sentinelleillä ja `VD`-lyhenteellä: **taulukko
on hypoteesi, laitteen oma sanoma on todiste.**

### Paljaan levyn boottiloki, 6.9.2026

Fläshätty ilman CC1101:tä tarkoituksella. Tämä on vertailukohta jota ei saa
myöhemmin takaisin, ja se tuotti yhden odottamattoman tuloksen.

```
[C][wmbus.transceiver:157]: Transceiver: CC1101
[C][wmbus.transceiver:131]:   IRQ Pin: GPIO4
[C][wmbus.transceiver:163]:   Frequency: 868.950 MHz
[C][wmbus_common:013]: wM-Bus Component v5.1.7-1.19.0-fe1b1e0:
[C][wmbus_common:015]:   Loaded drivers:
```

**Mikään ei kerro että radiota ei ole kiinni.** Komponentti tulostaa
kokoonpanonsa boottissa riippumatta siitä vastaako piiri SPI:llä, eikä
mitään vikailmoitusta tule.

Tämä on eri kuin stiebelissä, jossa MCP2515:n puuttuminen tuottaa rivin
`canbus is marked FAILED: unspecified` ja kytkentävian tunnistaa ennen kuin
väylään koskee. Kokoonpanotuloste ei siis erottele mitään.

**Mutta tässä luki että kytkennän oikeellisuus ei ole todettavissa lokista, ja
se on väärin.** Tarkistus on olemassa, kahdessa kerroksessa piilossa:

```
[VV][CC1101]: part: 00, version: XX
```

Se tulostuu tagilla `CC1101` **VERY_VERBOSE-tasolla setup-vaiheessa**, ja
`version`-rekisteri on se ainoa todiste SPI:stä päästä päähän: **arvon pitää
olla `04` tai `14`.** Osanumeroon ei voi luottaa, koska ajurin oma tarkistus
kaatuu vain jos se on jotain muuta kuin nolla — ja kuollut väylä lukee nollaa.
`Invalid part number` ei siis tule koskaan väärästä kytkennästä.

Kaksi syytä miksi se on jäänyt näkemättä:

- **Taso on DEBUG**, ja rivi on VV:llä. VV:n voi nostaa ja SPI-tulvan voi
  vaientaa tagikohtaisesti `logs:`-lohkossa — aiempi kommentti hylkäsi VV:n
  tulvan takia eikä kokeillut suodatinta. YAMLissa on ohje siihen, mutta taso
  on tarkoituksella DEBUG: VV maksaa megatavun lokia tunnissa ja CPU-kuormaa
  eikä anna vastineeksi mitään ilman sarjaporttia.
- **API-lokivirta ei näe setup-vaihetta.** `esphome logs` liittyy vasta kun
  laite on verkossa, joten radion setup, `Receiver task created` ja mahdollinen
  paniikin backtrace ovat jo menneet. Nämä rivit näkee vain **sarjaportista.**

Seuraus vianetsintään: jos kehyksiä ei tule, **loki erottaa syyt toisistaan
vasta kun se luetaan sarjaportista VV-tasolla.** Ilman sitä väärä kytkentä,
väärä taajuus, hiljainen mittari ja kehystä kokoamaton vastaanotin näyttävät
lokissa samalta — nollalta.

Boottilokin vertaaminen kytkennän jälkeen tähän kertoo kuitenkin yhden asian:
**jos tulosteeseen ilmestyy uusia rivejä radion kanssa, komponentti kysyy
piiriltä jotain.** Jos loki on identtinen, se ei kysy — ja silloin yllä oleva
päättely pätee sellaisenaan.

`Loaded drivers:` on tyhjä koska mittarilohkoa ei ole. Se tarkoittaa että
58,3 %:n flash-luku on **ilman ajureita**.

Versio raportoituu **`v5.1.7`**, eli kiinnitetty commit on yhtä julkaisua
uudempi kuin `5.1.6`. Se vahvistaa numerolla mitä "julkaisematon koodi"
tarkoittaa tässä.

WiFi työpöydällä **−56 dBm**, verkko `IoT`, `axioma.local` /
192.168.1.119. Se on hyvä lukema, mutta se on mitattu pöydällä — asennuspaikan
lukema on eri asia ja se on se joka ratkaisee.

Sivuhuomio joka ei vaadi toimia: ESPHome ehdottaa `sram1_as_iram: true`
(+40 kt IRAMia). IRAM on 60,6 %:ssa, joten tilaa on — merkitty siltä varalta
että se joskus loppuu.

### Validoitu

```
podman exec esphome esphome config /config/axioma.effection.yaml
INFO Configuration is valid!
```

ESPHome 2026.8.2. Tuloste vahvistaa `radio_type: CC1101`,
`frequency: 868950000.0` ja `type: esp-idf` — **kehysvaraus jota tässä
tiedostossa pidettiin auki on tarpeeton**, ESPHome valitsee esp-idf:n (5.5.5)
oletuksena.

`GPIO5 is a strapping PIN` -varoitus tulee jokaisella ajolla eikä vaadi
toimia. Se on juuri se nasta joka on yllä perusteltu turvalliseksi.

**Tämä ei tarkoita että radio toimii.** Validointi tarkoittaa että ESPHome
suostuu kääntämään; sama todistusvoima kaatoi stiebelissä kaksi oletusta
peräkkäin. Rautaa ei ole kytketty.

### Ajuri on `q400`

Mittarin valmistajan nimeä ei ole ajurina. Qalcosonic W1 tunnistuu
automaattisesti huonosti, mutta `q400` lukee sen; komponentti tarjoaa ajurit
suoraan wmbusmetersista.

Julkaistussa `q400`-tulosteessa näkyvät kentät: `total_m3`,
`consumption_at_set_date_m3`, `meter_datetime`, `set_datetime`, `status` ja
`rssi_dbm`. **Lämpötilaa ei ole siinä listassa**, vaikka W1 sellaisen mittaa ja
vaikka tämä tiedosto on luvannut `Veden lämpötila` -entiteetin. Se on nyt
kommentoitu kaksinkertaisesti ja odottaa ensimmäistä purettua telegrammia —
mikä on sama sääntö kuin Meter ID:llä: **laitteen oma sanoma voittaa
taulukon.**

### Alustatuki

**ESP8266:ta ei tueta**, ja käännös kertoo miksi se ei ole mielivaltainen
rajaus. Valmis image on **1 069 167 tavua** — yli megatavun, ja se on
*kuunteleva* konfiguraatio ilman yhtään mittarianturia:

```
RAM:   [===       ]  27.3% (used 49260 bytes from 180736 bytes)
Flash: [======    ]  58.3% (used 1069167 bytes from 1835008 bytes)
```

D1 minin sovelluspartitio on OTA:n kanssa noin megatavu, eli tämä ei
yksinkertaisesti mahtuisi. Kysymys jota tässä repossa pohdittiin muistin ja
nastojen kannalta ratkeaa siis kokoon, ja ratkeaa selvästi.

**Vertailu repon muihin on paikallaan, koska tämä on selvästi raskain:**

| | Flash | RAM |
|---|---|---|
| stiebel, vaihe 1 | 45,2 % | 40,0 % |
| aidon | 46,8 % | 53,3 % |
| **axioma** | **58,3 %** | **27,3 %** |

Ero tulee wmbusmetersin ajurikoodista. RAM on väljin koko repossa, koska
ESP32:ssa sitä on enemmän — muistista ei siis tule ongelmaa, flashista voisi.
Jäljellä on noin 765 kt, ja mittarilohko lisää siihen vielä `q400`-ajurin. Se
mahtuu, mutta **jos joskus houkuttaa kääntää kaikki ajurit mukaan, tämä on se
luku jota vasten sitä katsoo.**

**ESP32-C3 on nimenomaisesti testattu** — päähaaran README mainitsee
`ESP32-C3 Super Mini`. Se poistaa toisen tässä repossa auki olleen
kysymyksen: jos levy joskus vaihtuu C3:een, komponentti ei ole este.

**Kehysvalinta on todentamatta.** Esimerkit käyttävät `esp-idf`:ää eikä tätä
ole kokeiltu Arduinolla. Jos käännös kaatuu johonkin muuhun kuin skeemaan, se
on ensimmäinen asia jota kannattaa vaihtaa.

---

# Lähteet

Repon tavan mukaan linkitetty eikä kopioitu.

- [StudioPieters — CC1101 868MHz SPI RF Module, Complete Guide](https://www.studiopieters.nl/cc1101-868mhz-spi-rf-module-complete-guide/)
  — piirros tästä nimenomaisesta moduulista nastanumeroineen, ja ESP32:n
  kytkentätaulukko joka vastaa tämän projektin omaa nastasta nastaan
- [Cirkit Designer — CC1101 Module](https://docs.cirkitdesigner.com/component/c132ba5f-b3e5-4906-a71e-12913dd93300/cc1101-module)
  — yleinen 10-nastainen kuvaus. **Ei päde tähän levyyn**, ja se on tässä
  esimerkkinä siitä miksi lähde pitää tarkistaa kuvaa vasten
- [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components)
  — käytetty ESPHome-komponentti
- [wmbusmeters](https://github.com/wmbusmeters/wmbusmeters) — ajurit, joista
  `q400` lukee Qalcosonic W1:n

# Hyödyllisiä hakusanoja

```
ESP32 CC1101 ESPHome wmbus
ESP32 CC1101 wiring
Wireless M-Bus ESPHome
Axioma Qalcosonic W1 Home Assistant
SzczepanLeon esphome-components
```

---

# Vianetsintä

## Ei dataa

Tarkista:

- antenni kiinni
- 868 MHz antenni
- SPI-kytkennät
- 3.3V käyttöjännite
- oikea GPIO-määritys

---

## Boot-loop

Yleensä:

- GDO0 väärässä pinnissä
- CS väärässä pinnissä

---

## Huono vastaanotto

- antenni liian lähellä metallia
- pitkä etäisyys mittariin
- huono antenni

---

# Seuraavat vaiheet

Rauta on kytketty ja komponentti kääntyy, joten jäljellä on sen selvittäminen
miksi kehyksiä ei tule. Järjestys on halvin ensin, ja kolme ensimmäistä eivät
vaadi keneltäkään mitään:

1. **Kuuntele 868,95 MHz arkena klo 6–18.** Oletusaikataulun sisällä, koska
   molemmat aiemmat mittaukset osuivat sen ulkopuolelle tai väärälle
   taajuudelle. Tämä on koko selvityksen ratkaisevin ja halvin testi.
2. **Todenna SPI sarjaportista VV-tasolla.** Etsi `[VV][CC1101]: part: 00,
   version: XX` ja vaadi `version` = `04` tai `14`. Samalla ajolla näkee
   setup-vaiheen rivit joita API-lokivirta ei näytä.
3. **Laske FIFO-kynnys paikallisessa työkopiossa:** `FIFOTHR` arvoon `0x00`.
   Testaa hypoteesin 3 johtavan epäilyn, eikä vaadi keneltäkään mitään.
4. **Lue mittarin konfiguraatio NFC:llä** — radiotila, moodi ja aikataulumaskit.
   Tämä nousi kolmannelta neljännelle, koska sovellusreitti on kiinni: ks.
   "Mittarin oma konfiguraatio on luettavissa NFC:llä".
5. **Kysy vesilaitokselta** radiotila, **moodi** ja AES-128-avain. Käynnistä
   tämä rinnalla heti, koska siihen menee kalenteriaikaa.
6. Pura ensimmäinen telegrammi ja varmista Meter ID sekä `q400`:n kenttänimet
   siitä, ei taulukosta.
7. Lisää mittari Home Assistantiin.

---

# Huomio

Axioma Qalcosonic W1 lähettää yleensä noin **16 sekunnin välein**, joten ensimmäistä telegrammia voi joutua odottamaan hetken.

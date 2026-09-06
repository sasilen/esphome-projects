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

## Levy vaihtui, ja perustelu on antenni

Tämä projekti oli varannut hyllyn **WROOM-32U:n** — 38-nastainen DevKitC,
micro-USB, u.FL-liitin ([kuva](esp32-devkitc-wroom32u.jpg)). Varaus purettiin.

**Perustelu oli väärä.** Ulkoantennia pidettiin täällä etuna sillä oletuksella
että vesimittari on ahtaassa metallikaapissa. Sitä ei ole missään mitattu eikä
kirjattu — ja ennen kaikkea **wM-Bus on radio**: mittari lähettää 868 MHz:llä ja
CC1101 kuulee sen kantaman sisältä mistä tahansa. Vastaanottimen sijoituspaikka
on siis vapaa muuttuja, ja se valitaan sieltä missä WiFi kuuluu. Aidonissa
vastaava pakko on aito, koska se levy on fyysisesti kiinni mittarin portissa;
täällä ei ole.

**Eikä u.FL ole lisäominaisuus.** WROOM-32U:ssa ei ole printattua antennia
lainkaan — ulkoinen antenni on sen pakko, ei bonus. Ilman sitä levyn WiFi olisi
heikompi kuin tavallisen WROOM-32:n.

Levy meni [hirviradalle](../hirvirata/), jossa etu on aito: ohjausrasia on ulkona
ja harjamoottorin kipinöinti häiritsee WiFiä, joten antenni kannattaa saada ulos
kotelosta ja kauas häiriölähteestä.

**Tilalle tuli tavallinen 30-nastainen DevKit**, jota on hyllyssä kaksi ja josta
pegasos ottaa toisen. Se on tähän parempi joka kohdassa jolla on merkitystä:

| | WROOM-32U | 30-nast. DevKit |
|---|---|---|
| Antenni | u.FL — **pakko** kiinnittää | printattu |
| USB | micro | USB-C |
| Siltapiiri | CP2102-luokkaa, **merkintä lukematta** | CH340C, luettu levyltä |
| Nastat | 38 | 30 — tämä tarvitsee 5 |

Se poistaa myös ajurikysymyksen, joka oli tässä tiedostossa avoimena: CH340C on
tunnistettu levyltä eikä arvattu valokuvasta.

**Ja antenneja on enää yksi.** Aiemmin tässä varoitettiin että levylle tulee
kaksi — 2,4 GHz u.FL WiFille ja 868 MHz SMA CC1101:lle — ja että ne menevät
sekaisin juuri siksi että molemmat ovat "se antenni". Printtiantennilla sitä
ansaa ei ole olemassa.

**CC1101-moduulissa on 26 MHz:n kide**, mikä on odotettu arvo.

**Antennikytkentä: pigtail tuli moduulin mukana.** Kuvatussa kulmassa ei näy
SMA- eikä u.FL-liitintä, joten antenni kytkeytyy sen kautta. Tämä on siis
kunnossa eikä sovitinta tarvita.

Jos pigtail joskus katoaa, neljännesaallon lanka on 868 MHz:llä noin 8,2 cm ja
kelpaa kokeiluihin ilman mitään liitintä.

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
väylään koskee. **Täällä sitä signaalia ei ole**, joten kytkennän oikeellisuus
ei ole todettavissa lokista — ainoa todiste on vastaanotettu kehys.

Seuraus vianetsintään: jos kehyksiä ei tule, **loki ei erota kolmea syytä
toisistaan** — väärä kytkentä, väärä taajuus tai mittari kantaman ulkopuolella.
Ne on eroteltava muuten, esimerkiksi mittaamalla SPI-linjat tai viemällä
vastaanotin lähemmäs mittaria.

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

1. Kytke ESP32 ja CC1101.
2. Lataa testi-ESPHome.
3. Tarkista loggerista näkyykö Meter ID.
4. Hanki AES-128-avain vesiyhtiöltä.
5. Lisää mittari Home Assistantiin.

---

# Huomio

Axioma Qalcosonic W1 lähettää yleensä noin **16 sekunnin välein**, joten ensimmäistä telegrammia voi joutua odottamaan hetken.

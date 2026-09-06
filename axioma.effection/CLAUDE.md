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

Kun Meter ID ja AES-avain ovat tiedossa:

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

---

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

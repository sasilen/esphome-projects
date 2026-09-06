# Axioma Effectio (Qalcosonic W1) → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [`CLAUDE.md`](CLAUDE.md).

Vesimittarin lukeminen langattomasti Home Assistantiin ESP32:lla ja CC1101-radiolla.
Mittari lähettää Wireless M-Bus -telegrammin 868,95 MHz:llä noin 16 sekunnin
välein; ESP32 vastaanottaa sen ja välittää ESPHomen natiivi-APIlla. Ei MQTT:tä.

**Tila: suunnitteluvaihe, konfiguraatio valmis.**
[`axioma.effection.yaml`](axioma.effection.yaml) on olemassa ja ajettavissa;
rauta on laatikossa mutta kytkemättä.

Konfiguraatio on tarkoituksella **pelkkä kuuntelija**. Se ei osaa lukea mittarin
arvoja eikä yritäkään — se todentaa radion, kytkennät, taajuuden ja kuuluvuuden,
ja kaikki neljä näkyvät yhdestä lokirivistä. Sensorilohko on tiedostossa
kommentoituna ja odottaa kahta asiaa: Meter ID:tä lokista ja AES-avainta
vesilaitokselta.

## Mittari

| Ominaisuus | Arvo |
|---|---|
| Valmistaja | Axioma |
| Malli | Effectio / Qalcosonic W1 |
| Tyyppi | LT-1621-MI001-034 |
| SN | 12345678 — paikanpitäjä, oikea lukee tyyppikilvestä |
| SW | 1.03 |
| Valmistusvuosi | 2024 |

Meter ID on todennäköisesti sarjanumero `12345678`, mutta se varmistetaan
vastaanotetusta telegrammista — älä oleta sitä etukäteen.

## Arkkitehtuuri

```
Axioma Water Meter
        │  Wireless M-Bus (868,95 MHz, T1)
        ▼
    CC1101 Radio
        │  SPI
        ▼
      ESP32
        │  ESPHome native API
        ▼
 Home Assistant
```

## Rauta

Kaikki löytyy varastosta, tätä projektia varten tilattuna:

- **ESP32 DevKit, 30-nastainen** — sama levy kuin
  [`../pegasos.enervent/esp32-devkit.jpg`](../pegasos.enervent/esp32-devkit.jpg).
  Printtiantenni, USB-C, CH340C-siltapiiri. Hyllyssä on kaksi tätä; pegasos
  ottaa toisen
- **CC1101 868 MHz**, Huerous — [kuva](cc1101-module.jpg), 26 MHz:n kide.
  Pigtail antennille tuli mukana
- **868 MHz omniantenni SMA-liittimellä, 2 kpl**, QWORK, taitettava

**Antenneja tulee yksi: 868 MHz CC1101:lle.** DevKitin WiFi on moduulin
printtiantennissa eikä vaadi osaa.

Hyllyn WROOM-32U ([kuva](esp32-devkitc-wroom32u.jpg)) oli tässä pitkään
varattuna, ja se olisi tuonut mukanaan toisen antennin — 2,4 GHz u.FL WiFille —
jonka voi sekoittaa 868 MHz:n SMA-antenniin juuri siksi että molemmat ovat "se
antenni". Se levy meni [hirviradalle](../hirvirata/), jossa ulkoantenni on aito
etu: siellä ohjausrasia on ulkona ja harjamoottorin kipinöinti häiritsee WiFiä,
joten antenni kannattaa saada ulos kotelosta ja kauas häiriölähteestä. Täällä
vastaavaa tarvetta ei ole — **wM-Bus on radio, joten vastaanottimen
sijoituspaikan valitset itse**, ja se valitaan sieltä mistä WiFi kuuluu.

## Kytkentä

Piirretty auki: [`wiring.svg`](wiring.svg).

| CC1101 | ESP32 | |
|---|---|---|
| VCC | 3.3V | **ei 5V eikä VIN** |
| GND | GND | |
| SI (MOSI) | GPIO23 | |
| SO (MISO) | GPIO19 | |
| SCK | GPIO18 | |
| CSN | GPIO5 | strapping-nasta, mutta haluaa HIGH:n ja CS lepää HIGH:ssa |
| GDO0 | GPIO4 | `irq_pin` |
| GDO2 | — | **jätä kytkemättä** |

**CC1101 toimii vain 3,3 voltilla — älä koskaan käytä 5 V:a.**

**GDO2 jää kytkemättä.** Nykyinen komponentti tarvitsee yhden keskeytyslinjan ja
se on GDO0. Vanha taulukko vei GDO2:n GPIO2:een, joka on **strapping-nasta** —
siihen ajava lähtö estää käynnistyksen, ja se on tämän projektin
vianetsintätaulukossa kirjattu boot-loop-syy.

Moduulien pinnijärjestys vaihtelee; tarkista oman moduulin silkkipainatus äläkä
luota yleiseen kaavioon.

## ESPHome

Komponentti: [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components).

**Komponentista on kaksi yhteensopimatonta sukupolvea yhtä aikaa elossa.**
`version_4` (viimeisin 4.1.4, 2/2025) käyttää yhtä `wmbus:`-lohkoa erillisine
`gdo0`/`gdo2`-pinneineen; **5.x** (viimeisin 5.1.6, 8/2025) on täysi uudelleen-
kirjoitus ja käyttää ESPHomen omaa `spi:`-komponenttia, `wmbus_radio:`-lohkoa
yhdellä `irq_pin`illä ja erillistä `wmbus_meter:`-lohkoa.

**Eikä kumpikaan julkaisu kelpaa tähän.** `5.1.6` on uusin, mutta viiden sarjan
uudelleenkirjoitus lähti SX1276:sta eikä tunne CC1101:tä lainkaan; CC1101 tuli
takaisin vasta päähaaraan, jota ei ole koskaan julkaistu. Julkaisua jossa olisi
sekä CC1101 että nykyskeema ei ole olemassa.

Lähde on siksi kiinnitetty **commit-tunnisteeseen**, ei haaraan eikä tagiin —
se on ainoa muoto joka antaa molemmat. Vaihtokauppana koodi on julkaisematonta.

Ajuri on **`q400`**, ei mittarin valmistajan nimi. Perustelut, versiotaulukko ja
kenttien tilanne ovat [`CLAUDE.md`](CLAUDE.md):ssä.

Konfiguraatio on **validoitu** ESPHome 2026.8.2:lla (`Configuration is valid!`).
Se tarkoittaa että ESPHome suostuu kääntämään sen — ei että radio toimii.
Rautaa ei ole kytketty.

```sh
podman exec esphome esphome config /config/axioma.effection.yaml
```

Kun radio toimii, loggeriin ilmestyy rivi tyyliin:

```
Received T1 A frame from 12345678 RSSI -70
```

Se kertoo kerralla neljä asiaa: radio toimii, kytkennät ovat oikein, taajuus on
oikein ja mittari kuuluu vastaanottimeen.

## Este: AES-128-avain

Qalcosonic W1 käyttää yleensä AES-128-salausta. Avain **ei** ole näytössä,
tyyppikilvessä eikä sarjanumerossa — se pitää pyytää vesilaitokselta,
isännöitsijältä, rakennuttajalta tai mittarin toimittajalta. Ilman sitä näkyvät
vain salatut telegrammit.

Tämä kannattaa laittaa liikkeelle heti, koska siihen menee kalenteriaikaa —
radion toimivuuden voi silti todentaa ennen avaimen saapumista.

## Vianetsintä

| Oire | Tarkista |
|---|---|
| Ei dataa | Antenni kiinni, 868 MHz antenni, SPI-kytkennät, 3,3 V, GPIO-määritykset |
| Boot-loop | GDO0 tai CS väärässä pinnissä — tai johto kiinni GPIO2:ssa |
| Huono vastaanotto | Antenni liian lähellä metallia, etäisyys, antennin laatu |

Ensimmäistä telegrammia voi joutua odottamaan hetken — lähetysväli on noin
16 sekuntia.

## Seuraavat vaiheet

1. Kytke ESP32 ja CC1101
2. Flashaa testikonfiguraatio
3. Tarkista loggerista näkyykö Meter ID
4. Hanki AES-128-avain vesiyhtiöltä
5. Lisää mittari Home Assistantiin

Yksityiskohdat: [`CLAUDE.md`](CLAUDE.md).

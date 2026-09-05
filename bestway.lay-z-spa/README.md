# Bestway Lay-Z-SPA → Home Assistant

> **Yleiskuva.** Tällä projektilla ei ole `CLAUDE.md`:tä — tekniset tiedot ovat upstreamin omassa dokumentaatiossa, ks. Linkit.

Poreammeen ohjaus ja seuranta Home Assistantista ESP8266:lla, joka asettuu pumpun
ja sen näyttöpaneelin väliin. Lämpötila, pumppu, lämmitin, kuplat ja ajastimet
näkyvät ja ohjautuvat HA:sta.

**Tila: käytössä.** Repon toinen valmis asennus [`../aidon/`](../aidon/):n rinnalla.

> **Poikkeus tämän repon linjasta:** tämä ei ole ESPHome-projekti eikä se käytä
> ESPHomen natiivi-APIa, vaan **MQTT:tä**. Muissa projekteissa MQTT on nimenomaan
> vältetty, mutta tässä valinta ei ole oma: firmware on valmis ja MQTT on sen
> ainoa kotiautomaatiorajapinta.

## Käytössä oleva versio

| | |
|---|---|
| Projekti | [visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA) |
| Julkaisu | 4.4.6 |
| Firmware-leima | `2024-10-07-1913` |
| Lisenssi | GPL-3.0 |

Rakennusohje (`bwc-manual.pdf`), tekninen dokumentaatio (`bwc_docs.xlsx`),
piirilevyn Gerber-tiedostot ja kytkentäkuvat tulevat kaikki upstreamin
julkaisupaketin mukana.

## Miten se toimii

Laite ei ole anturi vaan **väliintulija**. Se irrotetaan pumpun näyttöpaneelin
lattakaapelista ja kytketään väliin, jolloin se sekä lukee pumpun ja näytön
välisen liikenteen että pystyy syöttämään omia näppäinpainalluksia. Pumppuun
itseensä ei tehdä muutoksia.

```
Pumppu (CIO)  ──lattakaapeli──  ESP8266 + tasonsiirrin  ──lattakaapeli──  Näyttö (DSP)
                                        │
                                        │  MQTT (+ oma web-UI)
                                        ▼
                                  Home Assistant
```

Firmware tukee sekä 4- että 6-johtimisia malleja ja useita CIO/DSP-tyyppejä;
tyyppi valitaan web-käyttöliittymästä, ei käännösaikana.

## Rauta

| Osa | Huom |
|---|---|
| ESP8266 NodeMCU 1.0 / D1 mini | **Ei ESP32** — firmware on ESP8266-only |
| 8-kanavainen kaksisuuntainen tasonsiirrin | Pumpun logiikka on 5 V |
| 6- tai 4-napainen uros- ja naarasliitin | JST-SM parempi kuin 0,1" rimaliitin |

Valmis piirilevy on **PCB_V2B** ([EasyEDA](https://oshwlab.com/visualapproach/bestway-wireless-controller-2_copy)),
ja sen Gerber-tiedostot ovat upstreamin `Code/PCB/`-hakemistossa. Lue `bwc-manual.pdf`
ennen kolvin lämmittämistä.

> **Irrota verkkopistoke ennen kuin kosket rautaan.** Pumpussa on 230 V.

## MQTT-rajapinta

Perusaihe (base topic) on oletuksena `layzspa`, muutettavissa web-UI:sta.

**Laite julkaisee** (retained):

| Aihe | Sisältö |
|---|---|
| `layzspa/message` | Tila JSONina: lämpötilat, pumppu, lämmitin, kuplat, virheet |
| `layzspa/times` | Käyttöajat ja laskurit |
| `layzspa/other` | Sekalaiset arvot, mm. sähkönkulutusarvio |
| `layzspa/button` | Viimeksi painettu näppäin |
| `layzspa/Status` | `Alive` / `Dead` — **Last Will**, tarkista tämä ennen kuin luotat muihin |
| `layzspa/MAC_Address`, `layzspa/MQTT_Connect_Count` | Diagnostiikka |
| `layzspa/reboot_time`, `layzspa/reboot_reason` | Edellisen uudelleenkäynnistyksen syy |
| `layzspa/get_config` | Nykyinen konfiguraatio |

**Laite kuuntelee:**

| Aihe | Käyttö |
|---|---|
| `layzspa/command` | Yksi komento |
| `layzspa/command_batch` | Komentojono |
| `layzspa/set_config` | Konfiguraation muutos |

Telemetrian oletusväli on 600 s, mutta tilamuutokset julkaistaan heti.
Kaikki tila-aiheet ovat retained, joten HA saa arvot heti käynnistyessään — mutta
retained-arvo on olemassa myös silloin kun laite on poissa. Tarkista `Status`
ennen kuin luotat lukemaan.

### Home Assistant

Firmware osaa **MQTT-autodiscoveryn** discovery-prefixillä `homeassistant`, joten
entiteetit ilmestyvät HA:han itsestään ilman käsin kirjoitettua YAMLia, kunhan
HA:n MQTT-integraatio on käytössä ja osoittaa samaan brokeriin.

Mukana on myös Prometheus-endpoint, jos mieluummin kerää mittarit sitä kautta.

## Kääntäminen ja flashaus

PlatformIO, ei ESPHome. Kloonaa tai lataa upstream ensin:

```sh
git clone https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA.git
cd WiFi-remote-for-Bestway-Lay-Z-SPA/Code
pio run                    # käännä
pio run -t upload          # flashaa USB:llä
pio run -t uploadfs        # flashaa LittleFS-tiedostojärjestelmä (web-UI)
```

Ensimmäisellä kerralla **molemmat** tarvitaan — pelkkä firmware ilman
tiedostojärjestelmää jättää web-UI:n tyhjäksi. Skripti `gzip_littlefs.py` pakkaa
web-tiedostot automaattisesti ennen `uploadfs`-vaihetta.

Myöhemmin OTA on käytännöllisempi, koska laite on pumpun sisällä. Se onnistuu
web-UI:n kautta tai ottamalla `platformio.ini`:stä `upload_protocol = espota` ja
`upload_port = layzspa.local` kommenteista pois.

Ensimmäisellä käynnistyksellä laite nostaa oman tukiaseman
(`Lay-Z-Spa-<chipid>`), jonka kautta WiFi-tunnukset syötetään. Sen jälkeen kaikki
asetukset — CIO/DSP-tyyppi, MQTT-palvelin, ajastimet — tehdään
web-käyttöliittymästä; `config.h`:ta ei tarvitse koskea.

## Muistilista firmwarea uudelleen ladattaessa

Aiemmassa paikallisessa työkopiossa oli yksi ero upstreamin oletuksiin, ja se
kannattaa tehdä uudelleen jos levy on D1 mini:

- `Code/platformio.ini`: ympäristön nimi on `[env:nodemcuv2]`, mutta `board`-rivin
  arvo oli `d1_mini` eikä `nodemcuv2`

Jos teet muitakin muutoksia upstreamin koodiin, kirjaa ne tähän — muuten seuraava
versiopäivitys pyyhkii ne huomaamatta. Jos muutoksia kertyy paljon, upstreamin
forkkaaminen on siistimpi tapa kuin lista README:ssä.

## Täydennettävää

Nämä tietää vain asentaja itse, ja ne kannattaa kirjata ylös ennen kuin unohtuvat:

- [ ] Altaan ja pumpun malli sekä vuosimalli
- [ ] Onko liitäntä 4- vai 6-johtiminen, ja mikä CIO/DSP-tyyppi web-UI:hin on valittu
- [ ] Onko käytössä PCB_V2B vai lankakytkentä
- [ ] MQTT-brokerin osoite ja se, tuleeko HA:n MQTT-integraatio samasta
- [ ] Käyttökokemukset: mikä on toiminut, mikä ei

## Linkit

- [Upstream-projekti](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA)
  — lataa firmware, manuaali ja PCB täältä
- [Kehityshaara `development_v4`](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA/tree/development_v4)
- [FAQ](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA/discussions/46)
  ja [keskustelut](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA/discussions)
- [PCB EasyEDA:ssa](https://oshwlab.com/visualapproach/bestway-wireless-controller-2_copy)

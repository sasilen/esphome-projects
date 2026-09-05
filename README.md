# esphome-projects

Kotiautomaatioprojekteja ESPHomella. Yhteinen tavoite kaikissa: lukea ja ohjata
taloteknistä laitetta **paikallisesti** Home Assistantista ilman valmistajan
pilvipalvelua. ESPHome-projekteissa myös ilman MQTT:tä — pelkkä natiivi-API.
Poikkeuksena [bestway.lay-z-spa](bestway.lay-z-spa/), joka on valmis
kolmannen osapuolen firmware ja jonka ainoa kotiautomaatiorajapinta on MQTT.

Home Assistant pyörii Podman-kontissa (Container-asennus), joten ESPHome-lisäosaa
ei ole käytettävissä. ESPHome ajetaan omana konttinaan `Network=host`-tilassa,
muuten mDNS ei toimi eikä OTA löydä levyjä.

## Projektit

| Projekti | Laite | Väylä / rajapinta | Rauta | Tila |
|---|---|---|---|---|
| [aidon](aidon/) | Aidon 7410 -sähkömittari | HAN-portti (RJ12), EFS2 ASCII 115200 8N1 | Wemos D1 mini (ESP8266) | **Käytössä** |
| [bestway.lay-z-spa](bestway.lay-z-spa/) | Bestway Lay-Z-SPA -poreallas | CIO/DSP-lattakaapeli → **MQTT** | ESP8266 + tasonsiirrin | **Käytössä**. Ei ESPHome, ks. alla |
| [hirvirata](hirvirata/) | Liikkuva maalitaulurata | — (H-silta, PWM) | Wemos D1 mini + L298N + 12 V vaihdemoottori | Suunnittelu, YAML-luonnos valmis |
| [stiebel.eltron](stiebel.eltron/) | Stiebel Eltron WPC 07 -lämpöpumppu | CAN 20 kbps | ESP8266/ESP32 + MCP2515 (5 V → 3,3 V -muutos) | Suunnittelu, rauta osin hankittu |
| [pegasos.enervent](pegasos.enervent/) | Enervent Pegasos Eco ECE -IV-kone | RS-485 / Modbus RTU (RJ11-huoltoliitin) | ESP32 + MAX485 | Suunnittelu |
| [axioma.effection](axioma.effection/) | Axioma Effectio / Qalcosonic W1 -vesimittari | Wireless M-Bus 868,95 MHz T1 | ESP32 + CC1101 | Suunnittelu |

### aidon — ensimmäinen valmis

Kolmen vaiheen teho, virta ja jännite Home Assistantissa 10 sekunnin
päivitysvälillä. Kustannus nolla euroa. Koko rakennuskertomus aktivoinnista
juotokseen ja vianetsintään on tiedostossa
[`aidon/BUILDLOG.md`](aidon/BUILDLOG.md).

Kaksi asiaa jotka kannattaa tietää ennen kuin aloittaa vastaavan:

- **HAN-portti on oletuksena kuollut.** Verkkoyhtiön on aktivoitava sekä
  rajapinta että 5 V:n syöttö. Tilaa se ensin — se on projektin ainoa vaihe jota
  ei voi nopeuttaa. Aktivoinnin toteaa itse: kun nastassa 1 on 5 V, se on tehty.
- Pyydä **EFS2**-profiilia, ei EFS:ää. Avoimen lähdekoodin lukijat osaavat vain
  ASCII-muotoisen EFS2:n.

Avoimena: WiFi-kuuluvuus mittarikaapissa (−87…−90 dBm luukku kiinni) on liian
heikko, ja heikko signaali nostaa virrankulutusta juuri kun ollaan portin
280 mA:n rajalla — oire näyttää virtaongelmalta vaikka syy on radio.

## Hakemiston rakenne

Jokainen projekti on oma hakemistonsa:

```
<projekti>/
├── README.md              yleiskuva
├── CLAUDE.md              tekniset tiedot ja perustelut
├── BUILDLOG.md            rakennuskertomus (vain rakennetuissa projekteissa)
├── <projekti>.yaml        ESPHome-konfiguraatio (jos olemassa)
├── secrets.yaml.example   mallipohja salaisuuksille
└── *.svg                  kytkentäkuvat
```

Dokumentit vastaavat kolmeen eri kysymykseen, ja aikamuoto kertoo mihin mikäkin
teksti kuuluu:

| Tiedosto | Nimitys | Kysymys | Aikamuoto |
|---|---|---|---|
| `README.md` | Yleiskuva | Mikä tämä on, ja kannattaako minun tehdä tämä? | preesens, käskymuoto |
| `CLAUDE.md` | Tekniset tiedot ja perustelut | Miten se on rakennettu ja miksi juuri näin? | preesens, toteava |
| `BUILDLOG.md` | Rakennuskertomus | Miten tähän päädyttiin? | imperfekti, minämuoto |

Näitä nimityksiä käytetään kaikkialla samoina, jotta samalle tiedostolle ei
synny kahta eri nimeä eri paikkoihin.

`BUILDLOG.md` on **päivätty tilannekuva jota ei päivitetä** — myös siltä osin kuin
se vanhenee. Miten asiat nyt ovat, sen kertovat README ja CLAUDE.md. Toistaiseksi
buildlog on vain [aidonilla](aidon/BUILDLOG.md).

Poikkeus on `bestway.lay-z-spa`, jolla ei ole `CLAUDE.md`:tä lainkaan — sen
tekniset yksityiskohdat ovat upstreamin omassa dokumentaatiossa.

## Salaisuudet

`secrets.yaml` **ei ole versionhallinnassa** eikä sitä lisätä sinne — juurihakemiston
`.gitignore` estää sen. Jokaisessa projektissa on `secrets.yaml.example`, josta
kopio:

```sh
cd hirvirata
cp secrets.yaml.example secrets.yaml
$EDITOR secrets.yaml
```

API-salausavaimen saa komennolla `esphome config <projekti>.yaml` tai
[ESPHomen API-dokumentaation](https://esphome.io/components/api.html)
avaingeneraattorista.

## Kääntäminen ja flashaus

```sh
esphome compile hirvirata/hirvirata.yaml     # käännä
esphome run     hirvirata/hirvirata.yaml     # käännä + flashaa (USB tai OTA)
esphome logs    hirvirata/hirvirata.yaml     # seuraa lokia
```

Podman-asennuksessa saman ajaa kontissa:

```sh
podman exec esphome esphome config /config/hirvirata.yaml
```

`bestway.lay-z-spa` kääntyy PlatformIOlla eikä ESPHomella — ks. sen oma README.

## bestway.lay-z-spa — poikkeus linjasta

Poreallasohjain on rakennettu ja käytössä, mutta se ei sovi muiden projektien
muottiin kahdella tavalla: se ei ole ESPHome-projekti vaan itsenäinen
PlatformIO/Arduino-firmware, ja **se käyttää MQTT:tä**. Firmware on valmista
kolmannen osapuolen työtä, eikä MQTT ole siinä oma valinta vaan sen ainoa
kotiautomaatiorajapinta.

Firmware:
[visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA](https://github.com/visualapproach/WiFi-remote-for-Bestway-Lay-Z-SPA),
käytössä julkaisu 4.4.6. Kytkentäperiaate, MQTT-aiheet ja käyttöönotto ovat
projektin [README:ssä](bestway.lay-z-spa/README.md).

## Kieli

Dokumentit ovat osin suomeksi, osin englanniksi sen mukaan kumpi oli kätevämpi
kirjoitushetkellä: aidon, hirvirata ja axioma.effection suomeksi, stiebel.eltron
ja pegasos.enervent englanniksi. Kunkin projektin README on samalla kielellä kuin
sen CLAUDE.md.

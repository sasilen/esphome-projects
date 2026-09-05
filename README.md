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
| [stiebel.eltron](stiebel.eltron/) | Stiebel Eltron WPC 07 -lämpöpumppu | CAN 20 kbps | ESP8266/ESP32 + MCP2515 (5 V → 3,3 V -muutos) | Suunnittelu, rauta osin hankittu, kuuntelu-YAML valmis |
| [pegasos.enervent](pegasos.enervent/) | Enervent Pegasos Eco ECE -IV-kone | RS-485 / Modbus RTU (RJ11-huoltoliitin) | ESP32 + MAX485 | Suunnittelu |
| [axioma.effection](axioma.effection/) | Axioma Effectio / Qalcosonic W1 -vesimittari | Wireless M-Bus 868,95 MHz T1 | ESP32 + CC1101 | Suunnittelu |

## Levyt ja varasto

Levyt ovat projektien kesken jaettu resurssi, ja riittävyys näkyy vasta kun
kaikki lasketaan yhteen.

| Levy | Käytössä | Varattu suunnitelmissa | Vapaana sen jälkeen |
|---|---|---|---|
| Wemos D1 mini (ESP8266-12F, CH340G, USB-C) | aidon, bestway.lay-z-spa | hirvirata, stiebel.eltron | **0** |
| ESP32 | — | pegasos.enervent, axioma.effection | 1 |

Kolme ESP32:ta ei ole kolme samanlaista, vaan 2 + 1:

| Levy | Kpl | Tuntomerkit | Kenelle |
|---|---|---|---|
| [30-nastainen DevKit](pegasos.enervent/esp32-devkit.jpg) | 2 | USB-C, CH340C, printattu PCB-antenni | pegasos.enervent, ja yksi vapaana |
| [38-nastainen DevKitC](axioma.effection/esp32-devkitc-wroom32u.jpg) | 1 | micro-USB, QFN-silta (CP2102-luokkaa), **WROOM-32U + u.FL** | axioma.effection |

Ainoa vapaa ESP32 on siis 30-nastainen PCB-antennilevy. Huomaa myös että
USB-siltapiiri vaihtuu levytyypin mukana, eli myös ajuri: CH34x vs. CP210x.
D1 minit ovat CH340G ja USB-C, eli sama CH34x-ajuri kuin diymoren ESP32:issa.

**Yksi asia kannattaa varmistaa D1 mineistä ennen ensimmäistä flashausta:**
myynti-ilmoitus lupasi "4MBit Flash Memory". ESP8266-12F:ssä on käytännössä aina
4 **MB** eli 32 Mbit, ja ESPHomen `board: d1_mini` olettaa juuri sen. Jos levyllä
oikeasti olisi 512 kB, OTA ei mahtuisi. Kyse on lähes varmasti ilmoituksen
kirjoitusvirheestä — todennettavissa käynnistyslokista tai `esptool flash_id`
-komennolla.

Minit menevät siis tasan eikä varalevyä jää, ESP32:ista jää yksi yli. Tämä on
huomionarvoista siksi, että **aidon on ainoa projekti jossa ESP8266 ei ole
makuasia**: HAN-portin virtabudjetti sulkee ESP32:n pois. Jos sen levy hajoaa,
tilalle ei ole mitään.

Jos varalevy halutaan, hirvirata on luonteva paikka vaihtaa ESP32:een — sen
CLAUDE.md sanoo suoraan että kumpi tahansa käy, kun taas aidonilla ja
stiebel.eltronilla on kirjattu peruste ESP8266:lle.

Moduulit:

- **MCP2515 + TJA1050**, 3 kpl (RUIZHI) → stiebel.eltron. Yksi omistetaan
  pysyväksi snifferiksi (TXD nostettuna), joten työjuoksuun jää kaksi.
- **L298N**, 5 kpl (ARCELI) → hirvirata.
- **DC-DC-buck, säädettävä 3 A, 5 kpl** → hirvirata ja stiebel.eltron. Määrä
  riittää molemmille kolmen jäädessä yli, eli aiempi huoli kilpailusta oli
  aiheeton. Lähtöjännite on **asetettava mittarilla ennen kuormaa**.
- **TTL ↔ RS-485 -moduuli, 5 kpl** (JZK, automaattinen suunnanvaihto) →
  pegasos.enervent. **Ei ole tavallinen MAX485-kortti**: DE/RE-ohjausta ei ole,
  joten kytkentä on neljä johdinta eikä viisi.
- **LM2596** → hirvirata, ja stiebel.eltron jos virta otetaan lämpöpumpulta.
  Varaston moduuli on **ADJ eli säädettävä**: lähtöjännite on asetettava
  mittarilla ennen kuin kuorma kytketään.
- **CC1101 868 MHz** ([kuva](axioma.effection/cc1101-module.jpg), 26 MHz:n kide)
  ja **868 MHz omniantenni SMA:lla, 2 kpl** → axioma.effection. ESP32:n oma
  2,4 GHz u.FL -antenni ja kaapeli tulivat DevKitC-setin mukana. Levylle tulee
  siis kaksi eri antennia — älä sekoita niitä.
- **BME280-anturikortti, 2 kpl** (APKLVSR,
  [kuva](pegasos.enervent/gybmep-sensor.jpg)). Molemmat pegasoksen laatikossa,
  samannäköisiä. Ei kuulu yhdenkään projektin suunnitelmaan eikä
  käyttötarkoitusta ole kirjattu mihinkään. Onko piiri oikeasti BME280 vai
  BMP280 on varmistamatta; ero on kosteusmittaus.
**SN65HVD230:aa ei ole.** Se on ollut stiebel.eltronin osalistalla varastossa
olevana ensimmäisestä commitista asti, mutta sitä ei ole tilaushistoriassa
eikä laatikossa. Väite oli virheellinen, ja seuraus on että stiebelin vaihe 2
tarvitsee ostetun lähetinvastaanottimen.

**RS-485-moduuli ei korvaa sitä**, vaikka sekin on differentiaalinen pari.
CAN vaatii että recessiivinen tila *päästetään irti* — siihen perustuu sekä
arbitrointi että kuittaus. RS-485-ajuri on push-pull ja ohjaa molempia tiloja,
ja näissä korteissa suunta vaihtuu vielä automaattisesti. Perustelu on
[stiebel.eltronin CLAUDE.md:ssä](stiebel.eltron/CLAUDE.md).

## Mitä puuttuu

Läpikäynti projekteittain. Vain ne osat joita ei ole kirjattu varastoon.

| Projekti | Puuttuu | Estääkö aloituksen |
|---|---|---|
| stiebel.eltron | 3,3 V:n CAN-lähetinvastaanotin vaiheeseen 2 (CAN Pal tai VP230) | Ei — vaihe 1 ei vaadi hankintoja |
| axioma.effection | — kaikki tilattu ja hyllyssä | Este on AES-128-avain, ei osa |
| pegasos.enervent | RJ11-kaapeli | Kyllä, mutta se on ainoa |
| hirvirata | Rajakytkimet, kääntöpyörä, kisko, kondensaattorit, sulake, DC-jakki | Kyllä |
| aidon | Schottky SS14/1N5819 ja 330 Ω — kovetukset jäivät tekemättä | Ei, laite on käytössä |
| bestway.lay-z-spa | — | — |

Yksi asia joka ei näy yksittäisen projektin listalta: **D1 mineissä ei ole
varaa.** Ks. levytaulukko yllä — neljästä kaksi on käytössä ja kaksi varattu.
Oheismoduuleista sen sijaan on yltäkylläisesti: bucke­ja, RS-485-kortteja ja
L298N:iä on viisi kutakin.

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
├── *.svg                  kytkentäkuvat
└── *.jpg                  valokuvat osista. Pienennä ja **poista metadata**
                           ennen committia — kamera tallentaa GPS-koordinaatit
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
se vanhenee. Miten asiat nyt ovat, sen kertovat README ja CLAUDE.md.

**Kun projekti valmistuu, sille kirjoitetaan BUILDLOG.** Se on kertomus siitä
miten rakennettiin: mitä tilattiin, mitä juotettiin, mikä meni pieleen ja mitä
tekisi toisin. Umpikujat ja väärät oletukset kuuluvat sinne — ne ovat tekstin
arvokkainta antia eivätkä mahdu mihinkään muualle. Kirjoita se pian valmistumisen
jälkeen, kun yksityiskohdat ovat vielä muistissa, ja päivää se.

Toistaiseksi buildlog on vain [aidonilla](aidon/BUILDLOG.md).

Poikkeus on `bestway.lay-z-spa`, jolla ei ole `CLAUDE.md`:tä lainkaan — sen
tekniset yksityiskohdat ovat upstreamin omassa dokumentaatiossa.

Repon juuressa on lisäksi oma [`CLAUDE.md`](CLAUDE.md), johon nämä konventiot on
koottu tiiviisti.

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

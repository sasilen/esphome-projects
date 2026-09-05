# Aidon 7410 HAN-portti → Home Assistant

Reaaliaikainen sähkönkulutus Aidon 7410 -mittarin HAN-portista Home Assistantiin
Wemos D1 minillä ja ESPHomella. Ei pilvipalvelua, ei MQTT:tä — pelkkä ESPHomen
natiivi-API.

**Tila: valmis ja tuotannossa.** Repon ainoa projekti joka ei ole suunnitelma.
Kolmen vaiheen teho, virta ja jännite päivittyvät 10 sekunnin välein.
Kustannus nolla euroa — kaikki osat löytyivät laatikosta.

## Arkkitehtuuri

```
Aidon 7410 (HAN / RJ12)
        │  115200 8N1, EFS2 ASCII, sanoma 10 s välein
        │  avokollektorilähtö + ylösveto 3,3 V:iin → käänteinen logiikka
        ▼
   Wemos D1 mini (ESP8266)
        │  ESPHome native API
        ▼
 Home Assistant (Podman-kontti)
```

ESP8266 eikä ESP32 nimenomaan virtabudjetin takia: HAN-portti antaa 250 mA
(ylivirtasuoja 280 mA). Sama syy miksi kaupallinen SlimmeLezer on ESP8266-pohjainen.

## Aloita tästä: portti on oletuksena kuollut

Verkkoyhtiön on aktivoitava sekä rajapinta että 5 V:n syöttö. Tämä on projektin
ainoa vaihe jota ei voi nopeuttaa, joten **tilaa se ensin** — älä rakenna mitään
ennen sitä. Porvoossa aktivointi tehdään OmaLiittymä-palvelussa tai sähköpostilla
asiakaspalveluun, maksutta.

Pyydä kolmea asiaa:

1. HAN-portin aktivointi
2. **EFS2-profiili**, ei EFS — avoimen lähdekoodin lukijat osaavat vain ASCII:n
3. Järjestelmämoduulin firmware vähintään 1.2.143

Aktivoinnin toteaa itse: kun nastassa 1 on 5 V, se on tehty. Vahvistusta ei
tarvitse odottaa.

## Kytkentä

| HAN (RJ12) | D1 mini |
|---|---|
| 1 (+5 V) | 5V |
| 2 (tietopyyntö) | 5V (sama reikä kuin nasta 1) |
| 3 + 6 (GND) | G |
| 5 (data, avokollektori) | D7 = GPIO13 |

Lisäksi **1 kΩ** D7:n ja 3V3:n välillä (ylösveto) ja **470 µF / 25 V** low-ESR
elektrolyytti 5V:n ja G:n välillä.

Ylösveto menee 3,3 V:iin eikä viiteen — piirin ainoa turvallisuuskriittinen
valinta. Avokollektorilähtö osaa vain vetää linjan alas, joten ylätason määrää
kokonaan ylösvedon jännite. 3,3 V:ssa D7 ei voi nähdä yli 3,3 V:a edes
vikatilanteessa mittarin päässä.

Kytkentäkaavio: [`kytkenta-lopullinen.svg`](kytkenta-lopullinen.svg),
juotossijoittelu: [`kolvaus-sijoittelu.svg`](kolvaus-sijoittelu.svg).

## ESPHome

Komponentti: [psvanstrom/esphome-p1reader](https://github.com/psvanstrom/esphome-p1reader),
`protocol: ascii`. Kolme kohtaa jotka kaatavat asennuksen jos ne unohtuvat:

1. **`logger: baud_rate: 0`** — D7 on GPIO13 eli hardware-UART0:n vaihtoehtoinen
   RX. Sarjaloggaus on sammutettava jotta UART vapautuu.
2. **`rx_pin: inverted: true`** — ylösveto tekee logiikasta käänteisen. Älä kopioi
   Slimmelezer-esimerkin uart-lohkoa; siinä lippua ei ole, koska kyseisellä
   levyllä on laitteistoinvertteri.
3. **Vastus tai transistori, ei molempia.** Transistorikytkennällä `inverted`
   jätetään pois.

Täysi konfiguraatio-ote ja sensorinimet ovat [`CLAUDE.md`](CLAUDE.md):ssä.
Flash 46,8 %, RAM 53,3 %.

> Itse `.yaml` ei ole vielä tässä repossa, vain olennaiset lohkot CLAUDE.md:ssä.

## Kuormanohjaus

Maalämpöpumpun EVU-estokosketin on kytketty ja toiminnassa: 230 V, Shelly-rele,
HA:ssa switch-entiteettinä "MLP EVU". Se on SG Readyn tilat 1 ja 2 eli yksi bitti
— kuormaa voi **siirtää pois** kalliilta tunneilta, mutta aurinkoylijäämää ei voi
**työntää** pumpulle.

Kaksi asiaa jotka kannattaa lukea CLAUDE.md:stä ennen automaatioiden kirjoittamista:

- **Polariteetti on intuition vastainen.** Rele ON = pumppu käy. HA:n switch
  tarkoittaa "lupa käydä", ei "esto päällä". Väärällä oletuksella kirjoitettu
  automaatio estää lämmityksen tammikuussa.
- **Vahtikoira on Auto ON, ei Auto OFF.** Koska OFF on estotila, Shellyn Auto ON
  -ajastin (esim. 7200 s) purkaa minkä tahansa eston itsestään ilman että HA:n
  tarvitsee olla hengissä. Auto OFF olisi tällä polariteetilla juuri väärinpäin.

Ylijäämän hyödyntämisen varsinainen reitti ei ole toinen SG Ready -tulo vaan
CAN-väylä: ks. [`../stiebel.eltron/`](../stiebel.eltron/).

## Avoimet asiat

1. **WiFi-kuuluvuus (tärkein).** −80 dBm kaapin luukku auki, −87…−90 kiinni.
   Liian heikko. Ikävä kytkös: heikolla signaalilla ESP lähettää täydellä teholla
   ja uusii paketteja, mikä nostaa virrankulutusta juuri portin 280 mA:n rajoilla
   — heikko radio voi laukaista hikkaustilan, ja oire näyttää virtaongelmalta.
   Ratkaisut halvimmasta: `power_save_mode: NONE` → levy kaapin ulkopuolelle
   (+10 dB) → D1 mini Pro ja u.FL-antenni → tukiasema lähemmäs.
2. **Loistehokentät pois käytöstä.** ESPHome lähettää yksikön `kVAR`, HA odottaa
   `kvar`. Tarkistettava onko korjattu uudemmassa versiossa.
3. **Piirin kovetukset tekemättä:** Schottky-diodi sarjaan 5 V -johtimeen ja
   330 Ω sarjaan D7:ään.

## Dokumentit

| Tiedosto | Sisältö |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Tiivistelmä, kytkentä, ESPHome-asetukset, kuormanohjaus, avoimet asiat |
| [`aidon-han-esphome-blogi.md`](aidon-han-esphome-blogi.md) | Koko rakennuskertomus: aktivointi, johdinkartoitus, juotos, flashaus, vianetsintä |

## Lähteet

- Aidon: `AIDONFD_RJ12_HAN_Interface_FI.pdf` — nastajärjestys ja sähköiset arvot
- [psvanstrom/esphome-p1reader](https://github.com/psvanstrom/esphome-p1reader) — käytetty komponentti
- [phlundblom/esphome-p1mini](https://github.com/phlundblom/esphome-p1mini) — vaihtoehto usealle mittarille
- [oma.datahub.fi](https://oma.datahub.fi) — tuntihistoria kuudelta vuodelta taaksepäin

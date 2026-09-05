# Aidon 7410 HAN-portti → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [`CLAUDE.md`](CLAUDE.md).
> Rakennuskertomus: [`BUILDLOG.md`](BUILDLOG.md).

Reaaliaikainen sähkönkulutus Aidon 7410 -mittarin HAN-portista Home Assistantiin
Wemos D1 minillä ja ESPHomella. Ei pilvipalvelua, ei MQTT:tä — pelkkä ESPHomen
natiivi-API.

**Tila: valmis ja tuotannossa.** Kolmen vaiheen teho, virta ja jännite päivittyvät
10 sekunnin välein. Kustannus nolla euroa — kaikki osat löytyivät laatikosta.
Uutena ostettuna osalista jää alle viiteen euroon.

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

ESP8266 eikä ESP32 virtabudjetin takia: HAN-portti antaa 250 mA, ylivirtasuoja
laukeaa 280 mA:ssa.

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

## Osalista

- Wemos D1 mini (ESP8266)
- RJ12–RJ12-kaapeli, 6-johtiminen — toinen pää katkaistaan
- 1 kΩ vastus
- 470 µF / 25 V low-ESR elektrolyytti

## Kytkentä

| HAN (RJ12) | D1 mini |
|---|---|
| 1 (+5 V) | 5V |
| 2 (tietopyyntö) | 5V (sama reikä kuin nasta 1) |
| 3 + 6 (GND) | G |
| 5 (data, avokollektori) | D7 = GPIO13 |

Lisäksi **1 kΩ D7:n ja 3V3:n välillä** (ylösveto) ja **470 µF** 5V:n ja G:n
välillä, miinusjalka G:hen.

Ylösveto menee **3,3 volttiin eikä viiteen**. Se on piirin ainoa
turvallisuuskriittinen valinta — perustelu on CLAUDE.md:ssä, mutta älä muuta sitä.

Kytkentäkaavio: [`kytkenta-lopullinen.svg`](kytkenta-lopullinen.svg),
juotossijoittelu: [`kolvaus-sijoittelu.svg`](kolvaus-sijoittelu.svg).
Johdinkartoitus yleismittarilla ennen juotosta: ks. [`BUILDLOG.md`](BUILDLOG.md) — se on se kohta jossa
levy kuolee jos huolimattelee.

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
— kuormaa voi siirtää pois kalliilta tunneilta, mutta aurinkoylijäämää ei voi
työntää pumpulle.

**Lue CLAUDE.md ennen kuin kirjoitat yhtään automaatiota tätä vasten.** Releen
polariteetti ja vahtikoiralogiikka ovat molemmat intuition vastaisia, ja väärä
oletus estää lämmityksen tammikuussa.

Ylijäämän varsinainen reitti on CAN-väylä, ei toinen SG Ready -tulo:
[`../stiebel.eltron/`](../stiebel.eltron/).

## Avoimet asiat

1. **WiFi-kuuluvuus (tärkein).** −80 dBm kaapin luukku auki, −87…−90 kiinni —
   liian heikko. Heikko signaali nostaa myös virrankulutusta, joten oire voi
   näyttää virtaongelmalta vaikka syy on radio.
2. **Loistehokentät pois käytöstä.** ESPHome lähettää `kVAR`, HA odottaa `kvar`.
3. **Piirin kovetukset tekemättä:** Schottky-diodi sarjaan 5 V -johtimeen ja
   330 Ω sarjaan D7:ään.

Ratkaisuvaihtoehdot ja perustelut: [`CLAUDE.md`](CLAUDE.md).

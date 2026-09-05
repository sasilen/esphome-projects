# Axioma Effectio (Qalcosonic W1) → Home Assistant

> **Yleiskuva ja rakennusohje.** Perustelut, testikonfiguraatio ja mitatut arvot: [`CLAUDE.md`](CLAUDE.md).

Vesimittarin lukeminen langattomasti Home Assistantiin ESP32:lla ja CC1101-radiolla.
Mittari lähettää Wireless M-Bus -telegrammin 868,95 MHz:llä noin 16 sekunnin
välein; ESP32 vastaanottaa sen ja välittää ESPHomen natiivi-APIlla. Ei MQTT:tä.

**Tila: suunnitteluvaihe.** Rauta on laatikossa mutta kytkemättä, eikä
testikonfiguraatiota ole vielä ajettu.

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

Kaikki löytyy jo varastosta, lisähankintoja ei tarvita:

- ESP32 DevKitC (ESP32-WROOM-32U)
- CC1101 868 MHz
- 868 MHz SMA-antenni

## Kytkentä

| CC1101 | ESP32 |
|---|---|
| VCC | 3.3V |
| GND | GND |
| SI (MOSI) | GPIO23 |
| SO (MISO) | GPIO19 |
| SCK | GPIO18 |
| CSN | GPIO5 |
| GDO0 | GPIO4 |
| GDO2 | GPIO2 |

**CC1101 toimii vain 3,3 voltilla — älä koskaan käytä 5 V:a.**

Moduulien pinnijärjestys vaihtelee; tarkista oman moduulin silkkipainatus äläkä
luota yleiseen kaavioon.

## ESPHome

Komponentti: [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components),
`wmbus`-platform. Testikonfiguraatio ja lopullinen sensorilohko ovat
[`CLAUDE.md`](CLAUDE.md):ssä.

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
| Boot-loop | GDO0 tai CS väärässä pinnissä |
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

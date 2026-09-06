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

- **ESP32 DevKitC (ESP32-WROOM-32U)**, DUBEUYEW-setti — [kuva](esp32-devkitc-wroom32u.jpg).
  Setissä tuli mukana 2,4 GHz:n antenni ja u.FL-kaapeli, mikä on tässä
  välttämätöntä: -32U:ssa ei ole printattua antennia lainkaan
- **CC1101 868 MHz**, Huerous — [kuva](cc1101-module.jpg), 26 MHz:n kide.
  Pigtail antennille tuli mukana
- **868 MHz omniantenni SMA-liittimellä, 2 kpl**, QWORK, taitettava

Levylle tulee siis **kaksi eri antennia**: 2,4 GHz u.FL ESP32:n WiFille ja
868 MHz SMA CC1101:lle. Eri taajuus, eri liitin, eri tarkoitus — ne on helppo
sekoittaa keskenään juuri siksi että molemmat ovat "se antenni".

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

Komponentti: [SzczepanLeon/esphome-components](https://github.com/SzczepanLeon/esphome-components).

**Komponentin skeema on muuttunut** sen jälkeen kun tämän projektin
muistiinpanot kirjoitettiin. `CLAUDE.md`:n testikonfiguraatio kuvaa vanhaa
muotoa: yksi `wmbus:`-lohko joka sisälsi SPI-pinnit ja erilliset `gdo0`/`gdo2`.
Nykyinen käyttää ESPHomen omaa `spi:`-komponenttia ja `wmbus_radio:`-lohkoa
jossa on yksi `irq_pin`. Ajettava versio on YAML-tiedostossa, ja **lähde on
kiinnitetty versiohaaraan eikä `@main`:iin** — juuri tämä skeemamuutos on
esimerkki siitä mitä liikkuva viittaus tekee.

Jos käännös valittaa tuntemattomasta avaimesta, tarkista komponentin README ja
vaihda haara. `esphome config` kertoo sen sekunnissa eikä vaadi rautaa.

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

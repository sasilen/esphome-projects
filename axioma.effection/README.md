# Axioma Effectio (Qalcosonic W1) → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [`CLAUDE.md`](CLAUDE.md).

Vesimittarin lukeminen langattomasti Home Assistantiin ESP32:lla ja CC1101-radiolla.
Mittari lähettää Wireless M-Bus -telegrammin 868,95 MHz:llä noin 16 sekunnin
välein; ESP32 vastaanottaa sen ja välittää ESPHomen natiivi-APIlla. Ei MQTT:tä.

**Tila: kytketty, kuuntelee, eikä mittari lähetä wM-Busia.** Vastaanotin on
todistetusti kunnossa — kohinapaketteja tulee läpi — mutta täysi lähetysikkuna
ma 7.9.2026 klo 10–18 tuotti **nolla kehystä**, ja yön kanssa yhteensä
kuusitoista tuntia nollaa.

**Todennäköisin syy: mittari on LoRaWAN-luennassa.** W1:ssä LoRaWAN ja wM-Bus
ovat erilliset liput, ja vesilaitoksella ei ole syytä pitää wM-Busia päällä jos
se lukee mittarin LoRaWANilla — paristo on mitoitettu 15 vuodeksi. LoRaWAN ei
ole vaihtoehtoinen paikallinen reitti, koska sen avaimet ovat verkkopalvelimella.
Perustelut: [`CLAUDE.md`](CLAUDE.md).

Konfiguraatio on tarkoituksella **pelkkä kuuntelija**. Se ei osaa lukea mittarin
arvoja eikä yritäkään — se todentaa radion, kytkennät, taajuuden ja kuuluvuuden.
Sensorilohko on tiedostossa kommentoituna ja odottaa kahta asiaa: Meter ID:tä
lokista ja AES-avainta vesilaitokselta.

**Kuuntele arkena klo 6–18.** Mittarin oletusaikataulu on ma–pe 6:00–18:00, ja
sen ulkopuolella radio on hiljaa kokonaan. Yöllä tai viikonloppuna mitattu
hiljaisuus ei kerro laitteistosta mitään.

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
printtiantennissa eikä vaadi osaa. Ulkoantennia ei tarvita, koska **wM-Bus on
radio** — vastaanottimen sijoituspaikan valitset itse, ja se valitaan sieltä
mistä WiFi kuuluu.

**ESP8266 ei kelpaa tähän, ja syy on koko.** Valmis image on 1 069 167 tavua ja
D1 minin sovelluspartitio on OTA:n kanssa noin megatavu — ei rajatapaus.
Vertailu repon muihin projekteihin on [`CLAUDE.md`](CLAUDE.md):ssä.

## Kytkentä

Piirretty auki: [`wiring.svg`](wiring.svg).

**Moduulissa ei ole nastamerkintöjä kummallakaan puolella.** Käännä levy niin
että **kide on ylöspäin** ja teksti `CC11010 868MHz Module` lukee vasemmassa
reunassa pystyssä — silloin kahdeksan reikää ovat oikealla ja järjestys on
ylhäältä alas tämä:

| # | CC1101 | ESP32 | Levyssä | |
|---|---|---|---|---|
| 1 | CSN | GPIO5 | `D5` | strapping, mutta haluaa HIGH:n ja CS lepää HIGH:ssa |
| 2 | GDO0 | GPIO4 | `D4` | `irq_pin` |
| 3 | GDO2 | — | — | **jätä kytkemättä** |
| 4 | MISO | GPIO19 | `D19` | |
| 5 | SCK | GPIO18 | `D18` | |
| 6 | MOSI | GPIO23 | `D23` | |
| 7 | GND | GND | `GND` | |
| 8 | VCC | 3.3V | `3V3` | **ei 5V eikä VIN** |

**DevKitissä `D`-numero on GPIO-numero** — `D18` on GPIO18. Wemosissa vastaava
ei päde: siellä `D5` on GPIO14. Kaikki seitsemän lankaa menevät DevKitin
ylempään riviin, alariviin ei tarvitse koskea.

Vasemmassa reunassa **GND — ANT — GND**; keskimmäinen on antenni.

**Reikien jako on 2,0 mm eikä 2,54 mm** — Dupont-hyppylangat eivät mahdu. Juota
ohut lanka suoraan.

**Mittaa VCC ja GND ennen virtaa.** Vain ne kaksi voivat rikkoa piirin, ja ne
tunnistaa ilman mitään taulukkoa: niiden väliltä vastuslukema nousee hitaasti
kondensaattorien varautuessa. Jos pari löytyy rivin alapäästä kuten yllä
luvataan, koko asento on todistettu yhdellä mittauksella.

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

## Flashaus

**Fläshää ennen kuin kytket.** Syy ei ole tapa vaan se että validointi ei ole
käännös: `esphome config` tarkisti skeeman, mutta lähde on julkaisematon commit
eikä riviäkään C++:aa ole käännetty. Ja paljas levy antaa vertailukohdan — kun
loki tiedetään ilman radiota, ensimmäinen hiljaisuus radion kanssa on kytkentä
tai kuuluvuus eikä kolmen tuntemattoman summa.

Sama erottelu on kirjattu [stiebelissä](../stiebel.eltron/CLAUDE.md) omaksi
luvukseen: SPI-vika ja väylävika näyttävät ulospäin samalta, eli mitään ei
tapahdu.

**1. Validoi.** Ilman rautaa, sekunneissa:

```sh
podman cp axioma.effection/axioma.effection.yaml esphome:/config/
podman exec esphome esphome config /config/axioma.effection.yaml
```

`INFO Configuration is valid!` tarkoittaa että skeema kelpaa. `GPIO5 is a
strapping PIN` -varoitus tulee joka kerta eikä vaadi toimia — ks. Kytkentä.

**2. Käännä ja kirjoita levylle.** Kontti on palvelimella ja levy tulee
todennäköisesti kannettavaan, joten sama reitti kuin aidonissa: ESPHomen
web-käyttöliittymästä **Install → Manual download**, ja `.bin` erikseen
levylle. Ensimmäinen käännös kestää minuutteja, koska se hakee toolchainin.

Levy on **USB-C** ja siltapiiri **CH340C**, joten koneella pitää olla CH34x-ajuri
— ei CP210x. Jos portti ei näy, `dmesg` kertoo kytkentähetkellä kumpi laite
ilmestyi.

```sh
sudo esptool --port /dev/ttyUSB0 --baud 115200 write_flash 0x0 firmware.bin
```

Käytä `factory`-tiedostoa, ei `-ota.bin`-versiota. `Permission denied` ratkeaa
komennolla `sudo usermod -a -G dialout $USER` ja uloskirjautumisella.

**3. Katso boottiloki paljaana.** Ei CC1101:tä, ei antennia. Kirjaa muistiin
mitä `wmbus_radio` sanoo kun radiota ei ole — se rivi on vertailukohta jota ei
saa myöhemmin takaisin.

WiFi yhdistyy ja API nousee. `WiFi-signaali` alkaa päivittyä minuutin välein.

**4. Mittaa kuuluvuus siinä paikassa johon levy on tulossa.** Varavirtalähde,
levy paikalleen, luukku kiinni jos sellainen on. `WiFi-signaali` kertoo
totuuden. Tämä on halpaa nyt ja kallista myöhemmin — aidonissa se mitattiin
liian myöhään ja on siellä yhä avointen asioiden kärjessä.

**5. Irrota USB. Kytke.** Seitsemän lankaa, GDO2 jää irti, 868 MHz:n antenni
CC1101:een **ennen** virtaa. Ks. [`wiring.svg`](wiring.svg).

**6. Virta takaisin ja odota.** Lähetysväli on ~16 s, mutta älä tulkitse
hiljaisuutta viaksi ennen kuin olet odottanut pari minuuttia.

Sen jälkeen kaikki päivitykset menevät OTA:na eikä levyä tarvitse enää irrottaa.

## Este 1: mittari ei lähetä wM-Busia

Vastaanottimen puoli on niin pitkälle todistettu kuin ilman kehystä voi: SPI ja
keskeytys toimivat, taajuus ja moodi ovat oikeat, ja FIFO-kynnyksen lasku 32:sta
neljään tavuun ei muuttanut mitään. Jäljelle jää mittari, ja LoRaWAN selittää
sen ilman että mitään on vialla.

**Ratkaisu on pyyntö, ei koodi:** onko `wMBus T1` päällä, ja voiko sen kytkeä.
Se on vesilaitoksen laite ja kieltävä vastaus on mahdollinen.

NFC kertoisi radiotilan suoraan ohi vesilaitoksen, mutta **puhelinreitti on
kiinni:** mittarin NFC on ISO 15693, jonka Android reitittää vain sallitulle
sovellukselle — ja sellaista ei ole saatavilla. Paljas napautus on hiljaa
vaikka tunniste olisi kentässä.

## Ohitus: PN5180 kaataa molemmat esteet

Noin viiden euron NFC-moduuli lukee mittarin suoraan ilman AES-avainta, ilman
lähetysikkunaa ja riippumatta siitä kumpaa radiota vesilaitos käyttää. Hinta on
se että vastaanotin on vietävä mittarin viereen — eli WiFin pitää kuulua siellä
missä mittari on. Ks. [`CLAUDE.md`](CLAUDE.md).

## Este 2: AES-128-avain

Qalcosonic W1 käyttää yleensä AES-128-salausta. Avain **ei** ole näytössä,
tyyppikilvessä eikä sarjanumerossa — se pitää pyytää vesilaitokselta,
isännöitsijältä, rakennuttajalta tai mittarin toimittajalta. Ilman sitä näkyvät
vain salatut telegrammit.

Tämä kannattaa laittaa liikkeelle heti, koska siihen menee kalenteriaikaa.
**Kysy samalla kertaa radiotila ja moodi** — moodi ratkaisee onko rautavalinta
oikea, eikä sitä kannata selvittää kahdessa erässä.

## Vianetsintä

| Oire | Tarkista |
|---|---|
| Ei dataa | Antenni kiinni, 868 MHz antenni, SPI-kytkennät, 3,3 V, GPIO-määritykset |
| Boot-loop | GDO0 tai CS väärässä pinnissä — tai johto kiinni GPIO2:ssa |
| Huono vastaanotto | Antenni liian lähellä metallia, etäisyys, antennin laatu |

Ensimmäistä telegrammia voi joutua odottamaan hetken — lähetysväli on noin
16 sekuntia **aikatauluikkunan sisällä.**

## Seuraavat vaiheet

1. Kuuntele 868,95 MHz arkena klo 6–18
2. Todenna SPI sarjaportista: `[VV][CC1101]: part: 00, version: XX`, jossa
   `version` on `04` tai `14`
3. Laske FIFO-kynnys `0x00`:aan paikallisessa työkopiossa ja katso nouseeko
   pakettitahti
4. Kysy vesilaitokselta radiotila, moodi ja AES-128-avain
5. Pura ensimmäinen telegrammi ja varmista Meter ID siitä
6. Lisää mittari Home Assistantiin

Yksityiskohdat: [`CLAUDE.md`](CLAUDE.md).

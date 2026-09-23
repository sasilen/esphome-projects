# Axioma Effectio (Qalcosonic W1) → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [`CLAUDE.md`](CLAUDE.md).

Vesimittarin lukeminen langattomasti Home Assistantiin ESP32:lla ja CC1101-radiolla.
Mittari lähettää Wireless M-Bus -telegrammin 868,95 MHz:llä noin 16 sekunnin
välein; ESP32 vastaanottaa sen ja välittää ESPHomen natiivi-APIlla. Ei MQTT:tä.

**Tila: kytketty, kuuntelee, eikä mittari lähetä wM-Busia.** Vastaanotin on
todistetusti kunnossa — kohinapaketteja tulee läpi — mutta täysi lähetysikkuna
ma 7.9.2026 klo 10–18 tuotti **nolla kehystä**, ja kaappaus jatkui siitä
katkeamatta seuraavaan päivään klo 14 asti. Kuuntelua on yhteensä noin
**36 tuntia ja nolla kehystä**, ikkunan sisä- ja ulkopuolelta.

**NFC-solmu on rakennettu ja se on verkossa.** PN5180 ja ESP32-C3 SuperMini
on juotettu yhteen, yhdeksän liitosta läpäisi mittaukset, ja levy nousee
verkkoon. Radiosolmu jää pystyyn siihen asti kunnes NFC on kertonut onko
wM-Bus ylipäätään päällä.

**Mutta PN5180 ei vastaa, ja kytkentä on poissuljettu.** Jokainen yhdeksästä
liitoksesta on mitattu molemmista päistä, ohjauslinjat ajettu ylös ehdoitta
ja todennettu, nastakartat luettu moduulin silkkipainatuksesta ja
valmistajan kuvasta, eikä naapurisiltoja ole. **Ainoa jäljellä oleva
epäilty on moduuli itse.**

Matkalla löytyi kaksi vikaa jotka eivät liity siihen: **C3:n `GPIO5`- ja
`GPIO6`-padit ovat kuolleet** (seitsemän muuta nastaa nousee, nämä eivät), ja
**`GPIO20`/`GPIO21` jumittavat käynnistyksen** vaikka ne ovat vapaita. `RST`
ja `NSS` on siksi reititetty langalla `GPIO1`:een ja `GPIO0`:aan. Levy on verkossa vakaasti aina kun
moduulia ei ajeta, joten **radio ei ole rikki** — epävakaus näyttää olevan
vuorovaikutusta jaetun syötön kautta, ja se nostaa puuttuvan 100 µF:n
takaisin listalle. Perustelut [`CLAUDE.md`](CLAUDE.md):ssä.

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

Moduuli on saapunut: **PN5180-NFC R1.1, 70 × 39 mm**, yksiosainen. Se saa oman
solmunsa **ESP32-C3 SuperMinillä** — radiosolmuun ei kosketa, koska NFC-luku on
se joka vastaa jäljellä olevaan kysymykseen wM-Busin tilasta. Konfiguraatio on
[`axioma-nfc.yaml`](axioma-nfc.yaml), kytkentä
[`nfc-c3-mount.svg`](nfc-c3-mount.svg).

## Este 2: AES-128-avain

Qalcosonic W1 käyttää yleensä AES-128-salausta. Avain **ei** ole näytössä,
tyyppikilvessä eikä sarjanumerossa — se pitää pyytää vesilaitokselta,
isännöitsijältä, rakennuttajalta tai mittarin toimittajalta. Ilman sitä näkyvät
vain salatut telegrammit.

Tämä kannattaa laittaa liikkeelle heti, koska siihen menee kalenteriaikaa.
**Kysy samalla kertaa radiotila ja moodi** — moodi ratkaisee onko rautavalinta
oikea, eikä sitä kannata selvittää kahdessa erässä.

## NFC-solmun fläshäys — ennen juottamista

**Fläshää C3 ensin, paljaana.** Se ei ole tapa vaan järjestys, ja siihen on
kaksi syytä:

- **`BOOT` ja `RESET` ovat levyn pinnalla**, ja rima tulee aivan niiden viereen.
  Paljaalla levyllä ne painuvat sormella.
- **Viallinen levy selviää ennen kuin siihen on juotettu yhdeksän liitosta.**
  Hyllyllä on kuusi C3:a; vaihto maksaa nyt minuutteja ja juotosten jälkeen
  illan.

Ja kolmas syy on siinä mitä fläshätään: `axioma-nfc.yaml` on vaiheessa 1
**pelkkä runko ilman SPI:tä ja ilman NFC-komponenttia.** WiFi, API ja OTA
todennetaan erillään siitä onko komponentin konfiguraatio oikein — kaksi
tuntematonta kerralla on yksi liikaa.

**1. Vie ja validoi.** Kontin `/config` on litteä ja `secrets.yaml` on siellä
jo jaettuna:

```sh
podman cp axioma.effection/axioma-nfc.yaml esphome:/config/
podman exec esphome esphome config /config/axioma-nfc.yaml
```

`INFO Configuration is valid!` ennen kuin USB-piuha kaivetaan esiin.

**2. Käännä ja ota `.bin` talteen.** ESPHomen web-käyttöliittymästä
**Install → Manual download → Factory format**. Ensimmäinen käännös hakee C3:n
toolchainin ja kestää minuutteja.

Käytä `factory`-tiedostoa äläkä `-ota.bin`-versiota. Jälkimmäinen on vain
sovellusosio ja olettaa että levyllä on jo bootloader ja partitiotaulu.

**3. Aseta levy latautustilaan.** Kumpi tahansa käy:

| | |
|---|---|
| Piuha kiinni | pidä `BOOT` pohjassa, napauta `RESET`, päästä `BOOT` |
| Piuha irti | pidä `BOOT` pohjassa ja kytke USB, päästä `BOOT` |

**4. Kirjoita.** C3 SuperMinissä on **natiivi USB eikä siltapiiriä** — ei
CH340C:tä kuten DevKitissä, eikä siis CH34x-ajuria. Portti on siksi
`/dev/ttyACM0` eikä `/dev/ttyUSB0`:

```sh
sudo esptool --chip esp32c3 --port /dev/ttyACM0 write_flash 0x0 firmware.factory.bin
```

Jos portti ei ilmesty, `dmesg` kertoo kytkentähetkellä mitä tapahtui. `Permission
denied` ratkeaa komennolla `sudo usermod -a -G dialout $USER` ja
uloskirjautumisella.

Natiivi USB **katoaa ja ilmestyy uudelleen** kirjoituksen jälkeen, koska piiri
käynnistyy uudelleen ja porttilaite luodaan uudestaan. Se näyttää katkokselta
eikä ole.

**5. Todenna laitteesta, älä komennon paluuarvosta.** Tämä on repon oma sääntö
ja se on ansaittu: `esphome run` on onnistunut näennäisesti samalla kun OTA ei
edes lähtenyt.

```sh
podman exec esphome esphome logs /config/axioma-nfc.yaml
```

Odotettu tulos on kolme riviä: WiFi yhdistyy, API nousee, ja **`Uptime` alkaa
juosta nollasta.** `Uptime` on ainoa rivi joka erottaa uudelleenkäynnistyksen
siitä että lokiasiakas vain liittyi — kokoonpanobanneri toistuu joka
liittymisellä eikä todista mitään.

`hardware_uart: USB_SERIAL_JTAG` on YAMLissa juuri tätä varten. Ilman sitä
sarjaportti on hiljaa ja toimiva levy näyttää kuolleelta.

**Anna liittymiselle pari minuuttia, ja älä käytä varayhteyttä merkkinä.**
Ensimmäinen boot liittyi vasta kuudennella kierroksella, ja siihen meni noin
kaksi minuuttia. Sitä ennen loki toistaa `Restarting adapter`, ja **jokainen
uudelleenkäynnistys vie varayhteyden alas ja takaisin** — AP siis vilkkuu eikä
pysy verkkolistassa. Puuttuva `Axioma NFC fallback` ei tarkoita ettei levy
käynnisty; se tarkoittaa yhtä hyvin että se on parhaillaan yrittämässä.

Sarjaportti on siksi ainoa rehellinen tapa katsoa tätä vaihetta, ja se on sama
sääntö kuin muuallakin tässä repossa: **API-lokivirta ei voi näyttää sitä miksi
laite ei ole verkossa**, koska se liittyy vasta kun laite on.

**6. Mittaa kuuluvuus siinä paikassa johon levy on tulossa.** Varavirtalähde,
levy mittarin viereen. Odotus on noin **−70 dBm**, koska samassa tilassa oleva
1-Wire-solmu lukee sitä. Tämä on halpaa nyt ja kallista juotosten jälkeen.

**6,5. Todenna nastat ennen kuin juotat.** Yksi käännös ja viisi mittausta,
ja se olisi säästänyt tässä projektissa illan: `GPIO5` ja `GPIO6`
osoittautuivat rikkinäisiksi vasta kun yhdeksän liitosta oli tehty ja
kytkentä mitattu kolmeen kertaan kunnossa olevaksi.

```yaml
switch:
  - platform: gpio
    pin: GPIO5          # toista jokaiselle käytettävälle nastalle
    name: "Testi GPIO5"
    restore_mode: ALWAYS_ON
```

Ota mukaan **yksi nasta jota et käytä** verrokiksi. Kaikkien pitää lukea
3,3 V maata vasten. Se joka ei lue, on rikki — ja levyn vaihtaminen maksaa
tässä vaiheessa minuutteja.

**Älä ota mukaan nastoja jotka ovat vastapuolen lähtöjä**, kuten `MISO` tai
`BUSY`: kahta lähtöä ei laiteta vastakkain.

Nastat eivät paljasta vikaansa käytössä ennen kuin niitä käytetään. Tämän
levyn `GPIO5` ja `GPIO6` eivät olleet missään aiemmassa konfiguraatiossa, eli
levy oli fläshätty ja ajanut WiFiä moitteetta niiden ollessa koko ajan
rikki.

**7. Irrota USB ja juota.** Järjestys on pakotettu, koska C3:n alle ei pääse
kolvilla sen jälkeen kun se on paikallaan: viisi lakkalankaa ensin, sitten rima,
sitten C3 päälle. Ks. [`nfc-c3-mount.svg`](nfc-c3-mount.svg) ja
[`CLAUDE.md`](CLAUDE.md).

**Tarkista `BUSY` ensimmäisenä jos jokin ei toimi.** Kun `GPIO8` ja `GPIO9`
vedetään irti, `GPIO10` jää rimaan yksin kahden tyhjän paikan taakse ilman
naapurien tukea. Se ei ole tiedetty vika vaan rakenteen heikoin kohta.

**Ja 100 µF PN5180:n viereen**, `+5V`:n ja `GND`:n väliin. **Tämä puuttui tämän
ohjeen ensimmäisestä versiosta**, ja se on juuri se osa joka on helpointa jättää
tekemättä: yhdeksän liitosta on lueteltu nimeltä, kondensaattori ei ole yksikään
niistä.

Lähetinpää piikittää satoja milliampeereja RF-purskeessa, ja sama syöttö ajaa
C3:n radiota. Notkahdus siinä hetkessä **näyttää verkkovirheeltä eikä
virtavialta** — `4-Way Handshake Timeout` ja `Handshake Failed` ovat sen
oireita, eivät heikon kentän oireita.

**Mittaa ennen kuin kytket virran.** Yleismittari, kolme asiaa tässä
järjestyksessä:

```
5V  ↔ GND      auki          nämä kolme voivat rikkoa jotain
3V3 ↔ GND      auki
5V  ↔ 3V3      auki
```

C3:n kaukorivissä järjestys on `5V` `GND` `3V3` — **maa on virtojen välissä**,
eli molemmat mahdolliset oikosulut ovat vierekkäisten nastojen välissä.

Sitten kaksi siltaa jotka eivät riko mitään mutta estävät käynnistyksen:

- **`GPIO3` ↔ `GPIO2`.** Kaukorivissä lukee `GPIO4` `GPIO3` `GPIO2` ja langat
  menevät kahteen ylempään. `GPIO2` on strapping, joten silta sitoo `MISO`:n
  siihen
- **Neljä irrotettua kohtaa auki.** C3:n `GPIO8` `GPIO9` `GPIO20` `GPIO21` ei
  saa olla yhteydessä JP1:n `MISO` `SCK` `GND` `GPIO` -padeihin

Ja vasta lopuksi yhdeksän jatkuvuusmittausta kytkentätaulukon mukaan.

**`GPIO8` ja `GPIO9` eivät ole irti pelkän strappingin takia.** Ne kytkeytyisivät
suoraan PN5180:n `MISO`- ja `SCK`-linjoihin, jotka on jo johdotettu `GPIO3`:een
ja `GPIO4`:ään. Boottihetkellä `GPIO8`:n on oltava ylhäällä ja `MISO` vetäisi sen
alas — **levy ei käynnistyisi lainkaan.** Se on myös se oire jos juotos on
siltautunut.

**Levyllä on yhä vaihe 1:n firmware, ja se on funktionaalinen testi.** Jos levy
nousee ja liittyy verkkoon juotosten jälkeen, yksikään strapping-nasta ei ole
pidossa. Mutta erottele kaksi syytä toisistaan sarjaportista, älä verkosta:

| Sarjaportti | Tulkinta |
|---|---|
| Tyhjä, tai toistuva teksti | **Juotos.** Strapping-nasta pidossa tai oikosulku |
| Boottaa, `Restarting adapter` toistuu | **Sama WiFi-ongelma kuin ennen juottamista** — ei liity liitoksiin |

**8. Vasta sitten vaihe 2.** Se on nyt aktiivisena `axioma-nfc.yaml`:ssä ja
lähtee OTA:na. USB-C jää `+5V`- ja `3.3V`-padien yläpuolelle, joten piuhaa ei
enää saa kätevästi kiinni.

Avaimet on **todennettu lähdekoodista** eikä README:stä, ja kolme asiaa meni
ensimmäisessä arvauksessa väärin: komponentin nimi on `qalcosonicnfc` ilman
alaviivaa, nastoilla on etuliite `pn5180_`, ja **erillistä `spi:`-lohkoa ei
tarvita** — komponentin `AUTO_LOAD` sisältää sen ja se ottaa kaikki kuusi
nastaa omina asetuksinaan. Lähde on kiinnitetty commit-tunnisteeseen, kuten
radiosolmussakin.

Ja pollausväli on **kolme tuntia eikä tunti.** Mittarin kommunikointikredit on
noin 20 min/kk eli 40 s/vrk, ja tunnin väli menee jo yli budjetin kahden
sekunnin luvulla. Perustelu ja mittausohje: [`CLAUDE.md`](CLAUDE.md).

## Vianetsintä

| Oire | Tarkista |
|---|---|
| Ei dataa | Antenni kiinni, 868 MHz antenni, SPI-kytkennät, 3,3 V, GPIO-määritykset |
| Boot-loop | GDO0 tai CS väärässä pinnissä — tai johto kiinni GPIO2:ssa |
| Huono vastaanotto | Antenni liian lähellä metallia, etäisyys, antennin laatu |

Ensimmäistä telegrammia voi joutua odottamaan hetken — lähetysväli on noin
16 sekuntia **aikatauluikkunan sisällä.**

## Seuraavat vaiheet

**NFC on nyt ensisijainen reitti**, koska se ei riipu kummastakaan esteestä —
36 tuntia kuuntelua tuotti nolla kehystä, eikä kolmea ensimmäistä
radiotoimenpidettä ole enää mielekästä jatkaa ennen kuin mittarin oma
konfiguraatio on luettu.

1. **Todenna että solmu pysyy pystyssä ilman NFC-komponenttia.** `Uptime`
   juoksee katkeamatta tunteja eikä `Association Expired` esiinny kertaakaan.
   Se todistaa `power_save_mode: NONE`:n ja rajaa vian komponenttiin
2. **Mittaa PN5180:n `+5V`, `3.3V` ja `BUSY` maata vasten** levy virroissa.
   Jatkuvuustesti ei kerro tuleeko jännite perille kuormassa — kylmä juotos
   virtalangassa lukee auki mutta ei kanna virtaa
3. Kytke vaihe 2 takaisin ja katso kaatuuko se ensimmäiseen lukuyritykseen
4. **Paikanna mittarin kela katsomalla**, kiinnitä löysästi, lue kerran
5. **Mittaa yhden luvun kesto** ja johda pollausväli siitä kertoimella 2–3
6. Lue mittarista radiotila, moodi ja aikataulumaskit — ne vastaavat siihen
   mitä radiosolmu ei ole vuorokausissa kertonut
7. Kysy vesilaitokselta rinnalla: onko `wMBus T1` päällä, missä moodissa, ja
   AES-128-avain. Tähän menee kalenteriaikaa, joten käynnistä se heti
8. Lisää mittari Home Assistantiin

**Radiosolmu jää pystyyn eikä sitä pureta** ennen kuin NFC on kertonut onko
wM-Bus ylipäätään päällä. Jos se osoittautuu päälle kytketyksi, jäljellä on
vielä SPI:n todennus sarjaportista (`[VV][CC1101]: part: 00, version: XX`,
jossa `version` on `04` tai `14`) ja ensimmäisen telegrammin purku.

Yksityiskohdat: [`CLAUDE.md`](CLAUDE.md).

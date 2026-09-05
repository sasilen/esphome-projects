# Aidon 7410 HAN-portti → Home Assistant (ESPHome)

## Tila

**Valmis ja tuotannossa.** Toisin kuin muut tämän hakemiston projektit, tämä ei ole
suunnitelma vaan toimiva asennus. Kolmen vaiheen teho, virta ja jännite näkyvät
Home Assistantissa 10 sekunnin päivitysvälillä.

Koko rakennuskertomus — aktivointi, johdinkartoitus, juotos, flashaus ja
vianetsintä — on tiedostossa `aidon-han-esphome-blogi.md`. Tämä tiedosto on
tiivistelmä ja avointen asioiden lista.

---

# Arkkitehtuuri

```
Aidon 7410 (HAN / RJ12)
        │
        │ 115200 8N1, EFS2 ASCII, sanoma 10 s välein
        │ avokollektorilähtö + ylösveto 3,3 V:iin → käänteinen logiikka
        ▼
   Wemos D1 mini (ESP8266)
        │ ESPHome native API
        ▼
 Home Assistant (Podman-kontti)
```

Ei MQTT:tä. ESPHome-lisäosaa ei ole käytettävissä (HA on Container-asennus), joten
ESPHome pyörii omana quadlettinaan — `Network=host` on pakollinen, muuten mDNS ei
toimi eikä OTA löydä levyä.

---

# HAN-portin nastajärjestys

| Nasta | Signaali |
|---|---|
| 1 | +5 V, max 250 mA (ylivirtasuoja 280 mA) |
| 2 | Tietopyyntö |
| 3 | GND |
| 4 | NC |
| 5 | Data, avoin kollektori |
| 6 | GND |

Nasta 4 on ainoa kytkemätön johdin — sen sijainti todistaa kartoituksen suunnan.

---

# Kytkentä (toteutunut)

| HAN | D1 mini |
|---|---|
| 1 (+5 V) | 5V |
| 2 (tietopyyntö) | 5V (sama reikä kuin nasta 1) |
| 3 + 6 (GND) | G |
| 5 (data) | D7 = GPIO13 |

Lisäksi:

- **1 kΩ** D7:n ja 3V3:n välillä — ylösveto
- **470 µF / 25 V** low-ESR elektrolyytti 5V:n ja G:n välillä, miinusjalka G:hen

## Miksi ylösveto menee 3,3 V:iin eikä viiteen

Tämä on piirin ainoa turvallisuuskriittinen valinta. Datalähtö on avokollektori:
se osaa vain vetää linjan alas, ei koskaan ajaa sitä ylös. Ylätaso määräytyy siis
kokonaan siitä mihin ylösveto on kytketty. 3,3 V:ssa D7 ei voi nähdä yli 3,3 V:a
edes vikatilanteessa mittarin päässä.

1 kΩ kuormittaa lähtöä 3,3 mA:lla — hyvin avokollektorin kyvyn sisällä — ja on
riittävän matala että nousuaika (~100 ns) on mitätön 115200 baudin 8,7 µs
bittiaikaan verrattuna. 10 kΩ olisi ollut rajatapaus.

## Kaksi kovetusta jotka jäivät tekemättä

- **Schottky-diodi (SS14 / 1N5819) sarjaan mittarin 5 V -johtimeen.** D1 Minin
  5V-nasta on useimmiten suoraan USB:n VBUS:issa ilman sarjadiodia, joten USB ja
  mittarin syöttö ovat rinnakkain aina kun molemmat ovat kiinni. 0,3 V:n häviö
  jättää LDO:lle 4,7 V eli runsaasti pelivaraa.
- **330 Ω sarjaan D7:ään.** Vakuutus sen varalta että kaapeli tehdään joskus
  uudestaan ja kartoitus osuu peilikuvaksi.

---

# ESPHome

Komponentti: **psvanstrom/esphome-p1reader**, `protocol: ascii`.

```yaml
esp8266:
  board: d1_mini
  restore_from_flash: true

logger:
  baud_rate: 0          # pakollinen: vapauttaa UART0:n
  level: DEBUG

uart:
  id: uart_bus
  rx_pin:
    number: GPIO13      # = D7
    inverted: true
  baud_rate: 115200
  rx_buffer_size: 3072

p1reader:
  - id: p1reader_esp
    uart_id: uart_bus
    protocol: ascii
```

Kolme kohtaa jotka kaatavat asennuksen jos ne unohtuvat:

1. **`baud_rate: 0`** — D7 on GPIO13 eli hardware-UART0:n vaihtoehtoinen RX.
   Sarjaloggaus on sammutettava jotta UART vapautuu.
2. **`inverted: true`** — tarvitaan koska ylösveto tekee logiikasta käänteisen.
   Älä kopioi Slimmelezer-esimerkin uart-lohkoa: siinä lippua ei ole, koska
   kyseisellä levyllä on laitteistoinvertteri.
3. **Vastus tai transistori, ei molempia.** Transistorikytkennällä `inverted`
   jätetään pois.

Sensorinimet ovat snake_case: `cumulative_active_import`,
`momentary_active_import_l1`, `voltage_l1`, `current_l1`.

Flash 46,8 %, RAM 53,3 %.

---

# Kuormanohjaus: mikä on jo olemassa

Blogitekstin lopun "sillä ei vain ole vielä mitään ohjattavaa" on vanhentunut.

Maalämpöpumpun **EVU-estokosketin on kytketty ja toiminnassa**: 230 V, ohjataan
Shelly-releellä, näkyy Home Assistantissa switch-entiteettinä ("MLP EVU").

Tämä ei ole täysi SG Ready vaan sen yksi bitti:

| SG Ready -tila | Käytettävissä | |
|---|---|---|
| 1 – esto | ✅ | EVU-kosketin kiinni |
| 2 – normaali | ✅ | EVU-kosketin auki |
| 3 – käynnistyssuositus | ❌ | vaatisi toisen tulon |
| 4 – käynnistyskäsky | ❌ | vaatisi toisen tulon |

Käytännön seuraus: kuormaa voi **siirtää pois** kalliilta tunneilta ja huipputehoa
voi leikata, mutta aurinkoylijäämää ei voi **työntää** pumpulle tällä liitännällä.

Ratkaisu ylijäämään ei kuitenkaan ole toinen SG Ready -tulo vaan CAN-väylä:
lämmityskäyrän tai asetusarvojen nosto on portaaton ja toimii pumpun oman
logiikan kanssa, kun taas tila 4 ohittaa sen. Ks. `../stiebel.eltron/`.

## Polariteetti (todennettu)

**Rele ON = pumppu käy. Rele OFF = pumppu estetty.**

Shellyn *Action on power on* = **Turn ON**, eli sähkökatkon jälkeen pumppu palaa
käyntiin ilman että HA:n tarvitsee tehdä mitään. Tämä on oikea asetus.

Huomaa että HA:n switch-entiteetin semantiikka on intuition vastainen: **päällä =
lupa käydä**, ei "esto päällä". Nimi "MLP EVU" ei kerro suuntaa. Väärällä
oletuksella kirjoitettu automaatio estää lämmityksen tammikuussa — harkitse
uudelleennimeämistä muotoon "MLP käyntilupa" tai vastaavaan.

## Vahtikoira: Auto ON, ei Auto OFF

Koska OFF on estotila, tarvittava asetus on Shellyn **Auto ON** -ajastin, esim.
7200 s. Silloin mikä tahansa esto purkautuu itsestään kahdessa tunnissa ilman että
HA:n tarvitsee olla hengissä purkamassa sitä. Vastaa EVU-eston alkuperäistä
suunnitteluoletusta rajallisesta kestosta.

Auto OFF olisi tällä polariteetilla juuri väärin päin: se *aiheuttaisi* eston.

## Jäljelle jäävä riski

Tällä polariteetilla **kuollut Shelly = pumppu estettynä pysyvästi**, koska
normaali käynti vaatii aktiivisesti vedetyn releen. Auto ON ei auta jos laite ei
saa virtaa lainkaan.

Tätä ei voi korjata Stiebelin puolelta: **EVU-tulo on 230 V:n jännitetulo**, ei
potentiaalivapaa kosketin, ja normaali käynti vaatii jännitteen läsnäolon. Auto ON
kattaa realistiset vikatilat (HA alhaalla, automaatio jumissa, verkko poikki),
mutta ei laiterikkoa.

Lepotilan kääntäminen onnistuu vain Shellyn puolelta, ja tapa riippuu mallista:

- **Pro-sarja** — koskettimet ovat SPDT (NO/NC/COM). Siirrä 230 V NC-navalle,
  jolloin releen lepotila päästää jännitteen läpi. Ei lisäosia.
- **Shelly 1 / Plus 1** — kosketin on pelkkä NO. Kääntäminen vaatii **välireleen**:
  pieni asennusrele jonka NC-koskettimen kautta EVU:n 230 V kulkee ja jonka kelaa
  Shelly vetää *estäessään*. Kuollut Shelly = kela lepää = NC kiinni = pumppu käy.

Kummassakin tapauksessa HA:n semantiikka kääntyy taas ympäri (ON = esto), ja Auto
ON vaihtuu Auto OFF:ksi. Nimeäminen pitää päivittää samalla.

**Halpa lievennys ilman kytkentämuutoksia:** HA-hälytys jos `MLP EVU` on
unavailable yli X minuuttia. Ei estä vikaa, mutta muuttaa hiljaisen vian
huomatuksi.

## Kysymys joka ratkaisee onko tämä vaivan arvoista

**Toimiiko WPM:n jäätymissuoja ja sähkövastus EVU-eston aikana?**

Jos toimivat, kuollut Shelly tammikuussa tarkoittaa kallista viikkoa — ei kylmää
taloa — ja koko kytkentämuutos on tarpeeton. Jos eivät, se on eri keskustelu.
Löytyy WPM:n ohjekirjasta, ei vaadi mittauksia.

## Vielä todennettava

**Seuraa mitä eston vapautuksen jälkeen tapahtuu.** Pitkä esto voi laukaista
sähkövastuksen, jolloin siirto maksaa enemmän kuin säästää. Tarkista WPM:n
asetukset.

---

# Avoimet asiat

## 1. WiFi-kuuluvuus (tärkein)

−80 dBm kaapin luukku auki, −87…−90 kiinni. Liian heikko; katkoja tulee.

Ikävä kytkös: heikolla signaalilla ESP lähettää täydellä teholla ja uusii
paketteja, mikä nostaa virrankulutusta juuri kun ollaan portin 280 mA:n rajoilla.
Heikko radio voi siis laukaista hikkaustilan, ja oire näyttää virtaongelmalta.

Ratkaisut halvimmasta ylöspäin: `power_save_mode: NONE` → levy kaapin ulkopuolelle
(+10 dB) → D1 mini Pro ja u.FL-antenni → tukiasema lähemmäs.

## 2. Loistehokentät pois käytöstä

ESPHome lähettää yksikön `kVAR`, HA odottaa `kvar`. Kentät jätettiin aluksi pois.
Tarkistettava onko korjattu uudemmassa ESPHome-versiossa.

## 3. Piirin kovetukset

Diodi ja sarjavastus yllä.

---

# Huomioita jotka maksoivat aikaa

- **Portti on oletuksena kuollut.** Verkkoyhtiön on aktivoitava sekä rajapinta
  että 5 V:n syöttö. Aktivoinnin voi todeta itse: kun nastassa 1 on 5 V, se on
  tehty. Tämä on projektin ainoa vaihe jota ei voi nopeuttaa — tilaa se ensin.
- **EFS2 vs EFS** oli turha huoli: 7410-moduuli ei tue EFS:ää lainkaan. Muilla
  moduuleilla ero on olennainen, koska avoimen lähdekoodin lukijat osaavat vain
  ASCII:n.
- **ESP8266 eikä ESP32** virtabudjetin takia. Sama syy miksi kaupallinen
  SlimmeLezer on ESP8266-pohjainen.
- **"Tuotanto yhteensä" ei ole paneelien tuotanto** vaan verkkoon syötetty
  ylijäämä. Mittari näkee vain nettovirtauksen; omakäyttö ei näy lainkaan.
  Kokonaiskuvaan tarvitaan invertterin oma data.

---

# Seuraavat askeleet

1. WiFi-kuuluvuus kuntoon — muuten kaikki muu on epävakaan datan varassa.
2. Vikatilan todentaminen ja Auto-OFF Shellylle (yllä).
3. **Lämmityskäyrän säätö HA:sta CAN-väylän kautta** — `../stiebel.eltron/`.
   Tämä on varsinainen aurinkoylijäämän hyödyntämisen reitti: käyrän nosto
   varastoi energiaa rakennusmassaan ja varaajaan portaattomasti. EVU-esto jää
   sen rinnalle karkeaksi työkaluksi huipputehon leikkaamiseen.
4. Takaisinkytkentä: EVU-ohjaus on avoin silmukka — et näe kuunteliko pumppu.
   CAN-luku sulkee silmukan. Sama ESP hoitaa sekä luvun että kirjoituksen.

---

# Lähteet

- Aidon: `AIDONFD_RJ12_HAN_Interface_FI.pdf` — nastajärjestys ja sähköiset arvot
- `github.com/psvanstrom/esphome-p1reader` — käytetty komponentti
- `github.com/phlundblom/esphome-p1mini` — vaihtoehto usealle mittarille
- `oma.datahub.fi` — tuntihistoria kuudelta vuodelta taaksepäin
- `kytkenta-lopullinen.svg`, `kolvaus-sijoittelu.svg` — kytkentäkaavio ja juotossijoittelu

# Talossa oli valmis anturiverkko, ja vika oli yhdessä rivissä ESPHomea

> **Rakennuskertomus.** Käyttämätön 1-Wire-tähti, unohtuneelta levyltä
> palautettu laitekartta, ja kolme peräkkäistä väärää diagnoosia ennen kuin
> oikea löytyi — komponentin lähdekoodista.
> Yleiskuva: [README.md](README.md). Tekniset tiedot: [`CLAUDE.md`](CLAUDE.md).

Talossa oli iso 1-Wire-tähti joka ei ollut käytössä. Ei dokumentaatiota, ei
tietoa siitä mitä siellä on, eikä isäntää. Yksi ilta myöhemmin siitä lukee
**38 laitetta**: kaksikymmentäkahdeksan lämpötila-anturia, kuusi ovikosketinta,
kolme leivinuunin termoparia ja yksi tuntematon tulo joka käy viiden minuutin
välein.

Väliin mahtui kolme väärää selitystä, kaksi peruttua neuvoa ja yksi koe joka
kumosi oman lähtöoletuksensa. Tämä kertomus on niistä, koska **oikea vastaus
oli koko ajan kolmen rivin päässä** ja etsin sitä kaikkialta muualta ensin.

---

## Vanha levy oli arvokkaampi kuin mikään mittaus

Verkko oli aikanaan ajettu Raspberryn GPIO:sta OWFS:llä. Kone oli sammutettu
vuosia sitten, mutta levy oli tallella — ja sieltä löytyi kaksi aineistoa jotka
eivät olleet samanarvoisia.

**`.txt`-listaukset vuodelta 2015 ovat mitattuja.** Ne ovat OWFS-hakemiston
listauksia, eli sitä mitä väylä raportoi. **PHP-kartta vuodelta 2020 on
kirjoitettu** — ihmisen tekemä annotaatio joka antaa nimet.

Ristiriidassa listaus voittaa olemassaolosta ja PHP nimistä, koska kumpikin on
ainoa lähde omalle asialleen. Vertailu ei tuottanut yhtään ristiriitaa vaan
aikajanan: väylällä oli 22 laitetta vuonna 2015 ja PHP:ssä 25 vuonna 2020, ja
ne viisi lisättyä ovat kaikki samaa tyyppiä — ovikattoantureita.

Listaukset olivat kumulatiivisia ja nimetty sen mukaan mitkä huoneet olivat
kulloinkin mukana. **Asennus eteni siis huone kerrallaan**, ja kunkin askeleen
uudet osoitteet ovat sen huoneen antureita.

## Neljä johdinta ja yksi vastus

Isäntä on ESP32-C3. Verkkoon lähtee neljä johdinta — data, syöttö ja kaksi
maata — ja **ylösveto jää isännän päähän**, GPIO4:n ja 3,3 voltin väliin.

![1-Wiren kytkentä](wiring.svg)

Kaksi jännitetasoa, ja se on tarkoitus. **Syöttö on 5 V ja ylösveto 3,3 V:**
DS18B20:n datanasta on avokollektori eli se osaa vain vetää alas, joten
ylätason määrää yksin ylösveto. Anturit saavat täyden jännitteen pitkälle
vedolle mutta datalinja heilahtaa vain 3,3 volttiin ja on turvallinen C3:lle.

Verkko päättyy RJ45-rasiaan, ja sen nastakartta oli oma tutkimuksensa: neljä
toisistaan riippumatonta reittiä päätyivät samaan tulokseen ennen kuin
pistokkeesta luettiin vahvistus.

![RJ45:n nastajärjestys](rj45.svg)

## Osoitteet laskettiin koskematta väylään

OWFS kirjoittaa osoitteen muodossa `28.FF265A750400`. ESPHome haluaa täyden
64-bittisen ROM-osoitteen, `0x0E0004755A26FF28`. Muunnos on sarjatavujen
käännös — ja se CRC-tavu jota OWFS ei näytä.

Ensimmäinen ajatukseni oli että osoitetta ei voi laskea, koska CRC puuttuu. Se
oli väärin. **Dallasin CRC8 ei ole satunnainen vaan laskettu muista
tavuista**, joten koko osoite on johdettavissa kun tuntee polynomin.

Kaksikymmentä osoitetta laskettiin näin, ennen kuin väylään oli koskettu.
Ensimmäinen luettelointi löysi niistä **yhdeksäntoista sellaisenaan**. Puuttuva
oli isännän pään DS18S20, ja samasta päästä katosi myös kosteusanturi — ne
olivat Raspberryn tyngässä eivätkä talon tähdessä.

Myöhemmin sama muunnos osui vielä viiteen ovikoskettimeen joita ei ollut
tarkoituskaan lukea. **Kolme riippumatonta vahvistusta menetelmälle.**

## Ja sitten neljätoista anturia palautti 85 astetta

Luettelointi löysi 38 laitetta. Lukeminen onnistui kahdeksalta.

Loki nimesi vian tarkasti:

```
[D][dallas.temp.sensor:162]: dropping reading caused by sensor reset
[D][dallas.temp.sensor:054]: 'Makuuhuone 3 itä': Got Temperature=nan°C
```

`dallas_temp` pudottaa lukeman vain yhdellä ehdolla: rekisterissä on **tasan
85,0 °C ja scratchpadin tavu 6 on 0x0C**. Se on DS18B20:n tehdasarvo, se mitä
rekisterissä on ennen ensimmäistä muunnosta.

Kolme asiaa seurasi yhtä aikaa. Anturi vastaa. CRC täsmää. **Muunnos ei
koskaan tapahtunut.** Kaapeli, liitokset ja käskyjen perillemeno olivat siis
kunnossa.

Ja jako oli kategorinen eikä asteittainen: **21 kierrosta, viisi onnistui
21/21 ja neljätoista epäonnistui 0/21**, ei yhtään poikkeusta kumpaankaan
suuntaan. Marginaalivika välkkyisi. 294 yritystä ilman ainuttakaan onnistumista
ei ole marginaali vaan kaksi eri populaatiota.

Toimivat viisi osoittautuivat olevan täsmälleen ne jotka puuttuvat vuoden 2015
listauksista ja esiintyvät vain vuoden 2020 kartassa — se ovikattolaajennus.
Koko 2015 asennettu tähti oli hiljaa.

## Kolme väärää selitystä

### Yksi: ylösveto on liian heikko

Ensimmäinen ajatus oli sähköinen. 38 laitetta, pitkä tähti, 4,7 kΩ:n
passiivinen ylösveto — nousureuna on liian loiva kaukaisimmille haaroille.

Perustelin sen vielä sillä että vanha isäntä oli DS9490R, jossa on aktiivinen
ylösveto. **Se ei pitänyt paikkaansa**: omistaja ajoi verkkoa Raspberryn
GPIO:sta, samalla 4,7 kΩ:lla.

![Ylösveto Raspberryn rimassa](rpi-pullup.jpg)

Kuva vanhasta toteutuksesta dokumentoi sen yhden asian jota mistään muualta ei
olisi saanut: **vastus on juotettu suoraan riman kahden nastan väliin.**
Verkossa itsessään ei ole ylösvetoa, eikä siis mitään mitä uusi isäntä voisi
periä.

### Kaksi: anturit ovat loiskäytöllä

Korjasin selityksen: Linuxin `w1`-alijärjestelmä kytkee muunnoksen ajaksi saman
GPIO:n ulostuloksi ja ajaa sen korkealle. Vastus rimassa on vain lepotilan
ylösveto; muunnoksen virran antaa GPIO itse. ESPHomessa sitä ei ole.

Siitä seurasi ennuste: loiskäytössä anturi käy muunnoksen ajan sisäisen
kondensaattorinsa varassa, joten **lyhyempi muunnos vaatisi vähemmän
varausta.** `resolution: 9` pudottaa muunnosajan 750 millisekunnista 94:ään —
kahdeksasosaan.

Asetin sen neljälletoista ja jätin viisi toimivaa verrokiksi.

**Tulos oli nolla.** Ei yhtään lukemaa, ei yhtäkään kierrosta, eivätkä
verrokit muuttuneet.

### Kolme: kondensaattori ei riitä

Päättelin nollatuloksesta että kondensaattori on liian pieni puskuroimaan
mitään, eli rajoite on virta eikä varaus — eikä virtavajetta voi lyhentää
ajallisesti. Sama päättely kaatoi ylösvedon laskemisen: jotta anturille jäisi
~3 V 1,5 mA:n vedolla, vastuksen olisi oltava alle 200 Ω.

Se oli oikea laskutoimitus ja **väärä johtopäätös**, kuten kohta selviää.

## Oikea vastaus oli ESPHomen omassa koodissa

Ennen kuin ehdin ehdottaa oman komponentin kirjoittamista, kävin lukemassa mitä
ESPHome tekee sen 750 millisekunnin odotuksella:

```cpp
void DallasTemperatureSensor::update() {
  this->send_command_(DALLAS_COMMAND_START_CONVERSION);
  this->set_timeout(..., this->millis_to_wait_for_conversion_(), [this] {
    ...
  });
}
```

**Väylää ei lukita.** `CONVERT T` lähetetään ja jatketaan `set_timeout`illa,
joten niiden 750 millisekunnin aikana pääsilmukka pyörii normaalisti — ja
jokainen toisen anturin `update()` aloittaa omalla `reset()`illään, joka vetää
linjan alas 480 mikrosekunniksi. **Se keskeyttää kesken olevan muunnoksen.**

Linuxin `w1` pitää väylämutexia koko tapahtuman ajan. Siinä oli se ero
Raspberryyn, jota haettiin koko ilta ylösvedosta, syötöstä ja kaapeloinnista.
**Ero oli isännän ohjelmistossa, ei sähkössä eikä talossa.**

Ja se selitti jälkikäteen molemmat asiat jotka olivat olleet ristiriitaisia:

- **Miksi jako oli täysin deterministinen.** `PollingComponent`-vaiheet
  lukitaan käynnistyksessä ja toistuvat tasan 60 000 millisekunnin välein,
  joten samat parit törmäävät identtisesti joka kierros.
- **Miksi `resolution: 9` ei auttanut.** Jos törmäys osuu ikkunan alkuun, sen
  lyhentäminen ei muuta mitään. Kokeen nollatulos ei siis kumonnutkaan sitä
  mitä luulin sen kumoavan.

Korjaus on YAMLia. Jokaiselle anturille `update_interval: never`, ja yksi
`interval`-lohko joka kutsuu ne läpi sekunnin välein:

```yaml
interval:
  - interval: 60s
    then:
      - lambda: 'id(t00).update();'
      - delay: 1s
      - lambda: 'id(t01).update();'
      ...
```

Ensimmäinen ajo: **46 lukemaa 49:stä.** Jokainen väylällä oleva anturi
raportoi. Yhdeksän tuntemattoman lisäämisen jälkeen **32/32.**

Kaapeli, syöttö ja ylösveto olivat koko ajan kunnossa.

## Lukemat vahvistivat nimikartan, ja paljastivat yhden virheen

Ulkona oli 14,7 °C. Rakenteen ulkopinnat erottuivat heti tiukkana ryhmänä
kaiken muun alapuolelta:

| | |
|---|---|
| 16,19 | Vaatehuone etelä ulko |
| **16,31** | **Makuuhuone 4 pohjoinen sisä** |
| 16,56 | Olohuone ulko |

Jokainen muu anturi oli 20,9–25,9 °C. Kolme paria neljästä oli oikein päin, ja
se on **riippumaton vahvistus koko PHP-kartasta johdetulle nimeämiselle** — ei
vain osoitteina vaan sijainteina.

Neljäs pari näytti väärinpäin: `Makuuhuone 4 pohjoinen sisä` istuu
ulkoryhmässä ja sen `ulko`-pari sisäryhmässä. Ilmeinen selitys oli että sisä ja
ulko ovat vaihtuneet vanhassa kartassa.

**Nimiä ei silti vaihdettu**, koska nimenvaihto synnyttää uuden entity_id:n ja
katkaisee historian — ja koska yön jäähtymiskäyrä ratkaisisi asian ilmaiseksi.

Se kannatti odottaa. Yön aikana varmistetut ulkopinnat **viilenivät** 0,19
astetta ja se kylmä MH4-anturi **lämpeni** saman verran. Se ei siis käyttäydy
ulkopinnan tavoin lainkaan: se on kylmä mutta lämpötilaltaan vakaa, ja
vaihdosoletus jäi vahvistamatta.

Yhden yön odottaminen esti väärän nimeämisen, jonka korjaaminen olisi maksanut
juuri sen historian jolla virhe olisi myöhemmin huomattu.

## Leivinuuni tunnistui askelkoosta

Väylällä oli kolme perheen `0x3B` laitetta joita ei ole missään vanhassa
aineistossa. Perheessä on kaksi eri piiriä: **DS1825**, tavallinen mittari, ja
**MAX31850**, termoparivahvistin.

`dallas_temp` ei tarkista perhekoodia lainkaan — se erikoiskäsittelee vain
DS18S20:n ja lukee kaiken muun DS18B20:nä. Ne siis luettiin ilman mitään
lisäystä. Ja lukemat kertoivat kumpi piiri on kyseessä:

```
23,50 · 23,75 · 24,00 · 24,25       ← 0,25 asteen portaat
25,0625                             ← 12 bitin DS18B20 samassa lokissa
```

**0,25 °C on MAX31850:n termoparitarkkuus**; DS1825 antaisi 0,0625:n portaita.
Perheen toinen vaihtoehto oli siis poissuljettu mittaamalla eikä päättelemällä.

Että formaatti ylipäätään toimi, on Maximin ansiota: MAX31850:n 14-bittinen
lukema on siirretty kaksi bittiä ylös, ja 0,25 astetta neljästi siirrettynä
osuu tasan samaan 1/16 asteen asteikkoon jota DS18B20 käyttää. Sama `raw / 16`
antaa oikean lukeman kummallakin.

Omistaja vahvisti että ne ovat leivinuunissa.

## Ovet, ja miksi kirjoitin oman komponentin

Kuusi perheen `0x12` laitetta osoittautuivat ovikoskettimiksi. ESPHomessa ei
ole DS2406:lle komponenttia, mutta suljetussa PR:ssä oli valmis `dallas_pio`.

Se ei kääntynyt: `one_wire`-rajapinta oli muuttunut kolmesta kohdasta
puolessatoista vuodessa. Menin lukemaan sen DS2406-lukua portatakseni sen — ja
löysin jotain paljon olennaisempaa.

Funktion oma kommentti sanoi `ALR=0 & IM=1`. Sen vakio oli `0b10000100`, eli
**ALR=1 ja IM=0**.

`IM` on Interrogation Mode, ja se erottaa luvun kirjoituksesta. Datalehti ja
riippumaton Arduino-toteutus sanovat molemmat että luku vaatii `IM=1`.

**Se valmis komponentti ei olisi lukenut ovia vaan kirjoittanut niiden
PIO-lähtöön.** Kääntymättömyys oli siis onnenpotku: jos se olisi kääntynyt,
olisin ajanut väylälle kirjoituksia joita en olisi osannut epäillä.

Oma komponentti on noin sata riviä ja tekee vain luvun. Ohjaustavu on `0x44`:

```
ALR=0 · IM=1 · TOG=0 · IC=0 · CHS=01 · CRC=00
  ↑      ↑                      ↑
älä koske lue                kanava A
 salpaan
```

## Ja salpa, joka oli ollut käyttämättä koko ajan

DS2406:ssa on **tapahtumasalpa**: se muistaa että tila muuttui, vaikka se olisi
jo palannut ennalleen. Juuri siksi vanhan toteutuksen listauksissa on
*Latch*-sarake, ja juuri siksi DS2406 on ovelle parempi kuin uudempi DS2413,
jossa sitä ei ole.

Koska anturit ajetaan sarjassa, ovia pollataan kerran minuutissa — ja nopea
avaus ja sulkeminen jäisi huomaamatta. `ALR=1` palauttaa salvan tilan **ja
nollaa sen samalla**, jolloin jokainen kierros vastaa kysymykseen *liikkuiko
ovi edellisen jälkeen*.

Yksi asia jäi epävarmaksi: raportoidaanko salpa ennen nollausta vai sen
jälkeen. Kun ALR otettiin käyttöön, PIOA:n salpa putosi nollaan kaikilla
kuudella — mutta se olisi tulos kummassakin tapauksessa.

**Todiste tuli vahingossa, ja toiselta kanavalta.** Yhden piirin toinen kanava
vaihtoi tilaa itsestään, ja sillä kierroksella salpa raportoitiin ykkösenä
samassa tavussa:

```
22:01:26  0xE3   A: taso=0 salpa=0    B: taso=0 salpa=1
```

Salpa ei siis ehtinyt nollautua ennen raportointia.

Ja samalla paljastui jotain muuta: **viidellä latchilla toinen kanava on
vakaasti korkealla eli kytkemättä, mutta kuudennella se käy viiden–kahdeksan
minuutin välein.** Se ei ole ovi. Se on jokin joka kytkeytyy päälle ja pois.

Se kuudes on juuri se latch jota ei ole vuoden 2020 kartassa. Se sai oman
entiteettinsä, ja rytmi tallentuu nyt — tunnistus käy vertaamalla mihin muuhun
se osuu yksiin.

## Mitä tästä jäi käteen

**Vanha levy oli arvokkaampi kuin mikään mittaus.** Kahdenkymmenen anturin
nimet, osoitteet ja asennusjärjestys tulivat kaikki sieltä. Mittaamalla ne
olisi saanut selville viikossa, jos silloinkaan.

**Kolme väärää selitystä olivat kaikki sähköisiä ja oikea oli ohjelmallinen.**
Jokainen niistä oli uskottava, ja jokainen kaatui halpaan kokeeseen. Se koe
joka "epäonnistui" oli niistä arvokkain: sen nollatulos oli tosi, vain sen
tulkinta oli väärä.

**Toisen koodin lukeminen kannatti kahdesti.** Se löysi ESPHomesta sen mitä
etsin, ja se löysi valmiista komponentista virheen joka olisi kirjoittanut
väylälle.

**Ympäristö näyttää aina koodivirheeltä.** Sama vanhentunut tila esiintyi
illan aikana neljällä tasolla: ESP-IDF:n välimuistissa, kontin hakemistossa,
`podman cp`:n hautaavassa kopiossa ja Python-moduulissa joka jäi prosessin
muistiin. Viimeinen niistä ilmoitti että kelvollinen asetusavain on
`invalid option`.

Kun jokin näyttää mahdottomalta, ympäristö on halvempi tarkistaa kuin koodi —
ja se on ollut oikea vastaus joka kerta.

## Mikä on auki

Yhdeksän lämpötila-anturia on väylällä ilman nimeä. Eräkoodi kertoo että ne
eivät ole yksi lisäys vaan vähintään kolme, ja että viisi niistä on ostettu
samaan aikaan kuin talon tunnetut anturit. Omistaja epäilee alakerran
dokumentoimatonta haaraa.

Sauna ei löytynyt. Kuusi ovea odottaa sitä että joku avaa ne yksi kerrallaan ja
nimeää ne. Ja yksi tuntematon tulo käy jossain viiden minuutin välein.

Väylä oli talossa koko ajan. Nyt se kertoo mitä siellä tapahtuu.

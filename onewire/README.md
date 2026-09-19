# Talon 1-Wire-väylä → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [CLAUDE.md](CLAUDE.md).

Talossa on **valmis 1-Wire-verkko jossa on DS18B20-antureita**, eikä se ole
käytössä. Kaapelointi ja anturit ovat siis molemmat jo paikoillaan; puuttuu vain
isäntä ja konfiguraatio.

Tämä on repon ensimmäinen projekti joka alkaa olemassa olevasta
infrastruktuurista. Kaikki muut ovat alkaneet tyhjästä laatikosta.

## Tila

**Väylä on kytketty ja se lukee.** 46 onnistunutta lukemaa 49:stä kolmen
kierroksen yli, eli jokainen väylällä oleva anturi raportoi.

| | |
|---|---|
| **38** | laitetta vastaa luetteloinnissa |
| **19** | DS18B20:tä luettavissa, nimettyinä huoneisiin |
| **3** | MAX31850-termoparia, todennäköisesti leivinuunissa |
| **6** | DS2406-kytkintuloa joita ESPHome ei lue |

**Korjaus oli yhden rivin asia, mutta se löytyi vasta neljäntenä.** Aluksi vain
kahdeksan anturia luki ja neljätoista palautti tehdasarvon 85 °C. Syy ei ollut
kaapelissa, syötössä eikä ylösvedossa vaan siinä että **`dallas_temp` ei lukitse
väylää muunnoksen ajaksi**: toisen anturin vuoro keskeytti edellisen kesken.
Linuxin w1-ajuri pitää mutexia, ESPHome ei — siinä oli koko ero vanhaan
Raspberry-toteutukseen.

Anturit ajetaan siksi sarjassa `interval`-lohkosta sekunnin välein.
Päättelyketju kumottuine välivaiheineen on [CLAUDE.md](CLAUDE.md):ssä; se on
tämän projektin opettavaisin osa.

Vanhan Raspberryn levyltä löytyi OWFS-toteutus vuosilta 2015–2020, ja sen
laitekartta on yhä se mistä nimet tulevat:

| | |
|---|---|
| **19** | DS18B20-lämpötila-anturia, nimettyinä huoneisiin |
| **1** | DS2438, lämpötila ja kosteus, tekninen tila — **ei enää vastaa** |
| **5** | DS2406-kytkintuloa varastossa, käyttötarkoitus tuntematon |

**Osoitteet oli laskettu oikein.** 19 kartan 20 osoitteesta löytyi väylältä
sellaisenaan, eli tavujärjestys ja CRC8 oli johdettu ilman virhettä koskematta
väylään. Puuttuva on isännän pään DS18S20, ja samasta päästä katosi DS2438.

Nimet kertovat mitä ne mittaavat: **rakennetta, eivät huoneilmaa.** Pareja
*sisä* ja *ulko* samassa paikassa, ikkunoiden ja ovien kohdilla, osa
katonrajaan. Taulukko osoitteineen on [CLAUDE.md](CLAUDE.md):ssä.

**Myös ryhmittely huoneittain on tallessa.** Asennus eteni vuonna 2015 huone
kerrallaan ja listaus otettiin joka vaiheessa, joten kunkin askeleen uudet
osoitteet ovat sen huoneen antureita. Ryhmittely täsmää PHP:n nimiin ilman
yhtään ristiriitaa — kaksi riippumatonta lähdettä samasta asennuksesta.

Kaksi seurausta:

- **Lattialämmityksen suunnitelma ei muutu.** Anturit eivät ole valussa, joten
  ne eivät korvaa [stiebel.eltronin](../stiebel.eltron/) 25 anturin
  jakotukkiasennusta. Se kysymys on suljettu.
- **DS2406:tta ESPHome ei lue.** Kuusi kytkintuloa jää siis lukematta. DS2438 ei
  enää vastaa väylälle lainkaan, joten se kysymys ratkesi itsestään.
  **MAX31850:n se sen sijaan lukee** ilman erillistä komponenttia — `dallas_temp`
  ei tarkista perhekoodia, ja piirin asteikko osuu DS18B20:n kanssa yksiin.

## Kytkentä

![Kartoituskytkentä](wiring.svg)

Kolme johdinta ja yksi vastus. **Ylösveto kuuluu isännän päähän**, datan ja
3,3 voltin väliin, ja niitä on yksi kappale koko verkolle — ei yhtä per haara,
koska rinnakkaiset ylösvedot laskisivat yhteisvastuksen liian pieneksi.

| RJ45 | Vanhan kaapelin johdin | C3 |
|---|---|---|
| **1** | musta | GND |
| **2** | punainen | **5V** |
| 3 | — | — |
| **4** | keltainen | **GPIO4**, ja **4,7 kΩ tästä 3V3:een** |
| **5** | valkoinen | GND |

**Nastat ovat pysyviä, värit eivät.** Taulukon värisarake kuvaa vanhaa
kaapelia; uuden patch-kaapelin värit ovat alempana.

Data nastassa 4 ja sen maa nastassa 5 on **sininen pari**; syöttö nastassa 2 ja
sen maa nastassa 1 on **oranssi pari**. Kumpikin signaali kulkee oman
paluujohtimensa kanssa samassa kierteessä — ja standardikaapelissa se toteutuu
itsestään, koska 1–2 ja 4–5 ovat pareja molemmissa nastajärjestyksissä.

**Syöttö on 5 V ja ylösveto 3,3 V.** Se ei ole epäjohdonmukaisuus vaan se mikä
on toiminut tässä talossa vuosia: anturit saavat täyden jännitteen pitkälle
vedolle, mutta datalinjan ylätason määrää yksin ylösveto, joten linja heilahtaa
vain 3,3 volttiin ja on turvallinen C3:lle.

**Ylösveto menee 3V3:een eikä viiteen.** Se on tämän kytkennän ainoa kohta jossa
virhe tuhoaa GPIO:n.

**Kytke molemmat maat, äläkä hajota pareja.** Maat ovat rinnan — ne yhdistyvät
sekä Raspberryn maatasossa että jokaisen anturin GND-nastassa — joten toisen
unohtaminen ei riko mitään, ja *juuri siksi* se jäisi huomaamatta kunnes pitkän
vedon jännitehäviö alkaisi oireilla kaukaisimmalla anturilla. Pidä data ja sen
maa samassa kierretyssä parissa ja syöttö ja sen maa toisessa.

**Johdinvärit ovat tässä asennuksessa sattumaa** — kaapeli on se joka sattui
olemaan käsillä — eivätkä ne tarkoita mitään. Nastanumerot sen sijaan ovat
pääteltävissä:

| Signaali | RJ45 | Raspberryn rima |
|---|---|---|
| DQ | **4** | 7 (GPIO4) |
| GND | **5** | 9 |
| VDD | kolmas käytössä oleva paikka | 1 |

Data ja paluu seuraavat siitä että **DS9490 on toiminut tässä verkossa**: sen
RJ11-pistoke ylettyy vain rasian keskimmäisiin nastoihin, joten muualla ne eivät
olisi olleet sovittimen ulottuvilla lainkaan. Syöttö ei seuraa siitä, mutta kun
kaksi paikkaa kolmesta on tiedossa, **kolmas näkyy vanhasta pistokkeesta
silmällä.** Koko ketju premisseineen on [CLAUDE.md](CLAUDE.md):ssä.

**Vanha kaapeli on mittalaite.** Sen toisessa päässä on Raspberryn rima, jonka
nastojen merkitys tiedetään: nasta 7 on GPIO4 eli data, nasta 1 on 3,3 V ja
nasta 6 on maa. Jatkuvuus RJ45-pistokkeesta rimaan antaa taulukon suoraan.

### Uusi kaapeli tehdaspistokkeesta, vanha jää paikalleen

![Ylösveto Raspberryn rimassa](rpi-pullup.jpg)

**Kuva on vanhasta toteutuksesta.** Se dokumentoi yhden asian joka ei selviäisi
mistään muualta: **ylösveto on isännän päässä**, juotettuna suoraan riman
kahden nastan väliin. Verkossa itsessään ei ole ylösvetoa.

C3:lle tehdään oma kaapeli **valmiista patch-kaapelista leikkaamalla toinen pää
irti**. Tehdaspuristus jää rasian päähän, ja Raspberryn kaapeli jää koskematta.

1. **Flashaa C3 ennen kuin kolviin kosket.** Minuutin työ, ja konfiguraatio
   putoaa epäiltyjen listalta pysyvästi. Penkillä oikea tulos on että kaikki
   kaksikymmentä anturia ovat `unavailable` — väylää ei ole.
2. **Mittaa kenttä ennen kuin leikkaat.** Se on ainoa tieto joka voisi muuttaa
   sijoituspaikkaa, ja sijoituspaikka määrää kaapelin pituuden.
3. **Leikkaa lyhyeksi.** Puoli metriä jos asennus sallii. Löysää ei jätetä
   varmuuden vuoksi: **tämä pätkä on sarjassa koko verkon kanssa**, toisin kuin
   yksittäinen haara.
4. **Tunnista neljä johdinta jatkuvuudella**, ei värillä. Kuorittu johdin ↔
   pistokkeen nasta. Tarvitaan nastat 1, 2, 4 ja 5.
5. **Vastus GPIO4:n ja 3V3:n väliin.** Rimassa se on nastojen 1 ja 7 välissä;
   C3:lla asento on eri mutta tehtävä sama. **3V3, ei 5V** — tämä on kytkennän
   ainoa kohta jossa virhe tuhoaa GPIO:n.
6. **Juota neljä johdinta.** Loput neljä katkaistaan eri mittaan tai
   eristetään. Jos käytät dupontia riman päällä, muista että **katkeileva
   datakontakti lukee nollana antureita** eikä erotu mitenkään muista syistä
   joilla väylä on hiljainen.
7. **Vedonpoisto.** C3 ei pidä kaapelia paikallaan omalla painollaan.

Nastat ovat samat molemmilla standardeilla; vain värit vaihtuvat. **Sininen
pari on nastoissa 4 ja 5 kummassakin**, joten datapari on varma:

| RJ45-nasta | T568B | T568A | C3 |
|---|---|---|---|
| 1 | valko-oranssi | valkovihreä | GND |
| 2 | oranssi | vihreä | 5V |
| 4 | sininen | sininen | GPIO4, data |
| 5 | valkosininen | valkosininen | GND |

Reunimmainen johdin kertoo kumpi standardi: oranssi on B, vihreä on A.

**Palautus on pistokkeen vaihto.** Raspberryn kaapeli on ehjä ja paikallaan,
joten vanhaan toteutukseen palataan irrottamalla C3:n pistoke ja työntämällä
vanha tilalle.

**Yksi isäntä kerrallaan** seuraa samasta: verkolla on yksi paikka, joten
molemmat kaapelit eivät mahdu kiinni yhtä aikaa. Sääntö ei jää muistin varaan.

Vanha kaapeli pysyy siis myös mittalaitteena. Sen kartta on tässä siltä
varalta että se joskus irrotetaan:

| Raspberryn nasta | Signaali | Johdin |
|---|---|---|
| 1 | 3,3 V | vain vastus, ei johdinta |
| 2 | 5 V | punainen |
| 6 ja 9 | GND | musta ja valkoinen |
| 7 | GPIO4, data | keltainen |

## Ennen kuin kytket isännän

Verkko on vieras, eikä siitä ole dokumentaatiota. Kolme mittausta, kaikki
yleismittarilla ja yhteensä viisi minuuttia:

1. **Mittaa jännite.** Verkon pitäisi olla kuollut. Jos johtimissa on
   jännitettä, jossain on toinen isäntä tai vanha syöttö yhä kiinni — ja se on
   löydettävä ennen kuin tähän lisätään toinen. **Kaksi isäntää samalla
   väylällä rikkoo ajoituksen molemmilta.**
2. **Etsi maa.** Se on johdin joka on yhteinen kaikille haaroille: maa soi
   kaikkialle, DQ ja VDD eivät. Valmiissa asennuksessa johdinväri ei kerro
   mitään, koska se riippuu siitä kuka kaapelin veti.
3. **Tarkista oikosulku.** DQ ja maa eivät saa soida keskenään. Jos soivat,
   jossain on vaurioitunut anturi tai puristunut kaapeli — ja koko väylä on
   silloin hiljainen riippumatta siitä mitä isäntä tekee.
4. **Mittaa DQ:n ja VDD:n väli.** Verkkoa on ajettu myös Raspberryn GPIO:sta,
   joka vaatii ulkoisen 4,7 kΩ:n ylösvedon — ja jos se asennettiin keskipisteeseen
   eikä Raspberryn päähän, se on yhä siellä. **~4,7 kΩ tarkoittaa ettei toista
   lisätä**; avoin tarkoittaa että omansa tarvitaan.

**Maa ensin, ja se on tärkeysjärjestys eikä tapa.** DQ:n ja VDD:n sekoittaminen
on toivuttavaa; maan ja VDD:n sekoittaminen ei ole.

## Kartoitusajo

![RJ45-nastajärjestys](rj45.svg)

Verkko päättyy RJ45:een, ja nastakartta on luettu — arvattavaa ei ole. Aiemmin
tässä oli kaksivaiheinen menettely, jossa DS9490-sovittimella luetteloitiin
väylä **kahdella johtimella** ennen kuin kolmatta kytkettiin. Se oli
turvallisuusrakennelma epävarmuutta vastaan: sovitin ajaa väylää loiskäytöllä
eikä anna syöttöä, joten VDD:tä ei tarvinnut arvata. **Se epävarmuus on
poissa**, joten kierros on tarpeeton.

`discovery.yaml` jää voimaan mutta eri syystä kuin alun perin. Sitä ei tarvita
selvittämään mitä väylällä on — se tiedetään, 25 laitetta nimineen. Se
tarvitaan tuottamaan **osoitteet ESPHomen omassa muodossa**: käsillä on
OWFS-muoto `28.FF265A750400`, ja ESPHome haluaa täyden 64-bittisen
ROM-osoitteen CRC:n kanssa. Sitä ei voi laskea OWFS-muodosta, mutta ESPHome
luetteloi sen itse.

### Kolme askelta, ja flashaus on ensimmäinen

1. **Flashaa [`onewire.yaml`](onewire.yaml) ennen kuin kolviin kosket.** Se
   erottaa vikaluokat: jos konfiguraatio on todettu toimivaksi, ensimmäinen
   tyhjä luettelo ei voi johtua siitä.
2. **Vie levy keskipisteeseen ja katso RSSI.** Varasto voi olla huono paikka
   radiolle, ja SuperMinin keraaminen antenni on tunnetusti heikko. Aidonin
   mittarikaapista on kirjattu −87…−90 dBm liian heikoksi.
3. **Siirrä kaapeli Raspberrystä C3:een** — ks. alla — ja katso täyttyvätkö
   anturit

**Vertaa luetteloa näihin kahteenkymmeneen.** ESPHome luetteloi käynnistyksessä
kaikki väylältä löytyvät osoitteet, ei vain niitä joille on määritelty anturi.
**Mikä tahansa ylimääräinen on lisätty vuoden 2020 kartan jälkeen** — ja
esimerkiksi saunaa ei kummassakaan vanhassa lähteessä ole, vaikka sellainen
voisi hyvin olla olemassa. Siksi lokitaso on `DEBUG` eikä `INFO`.

Luettelo tulostuu CONFIG-tason viesteinä, mutta **`level: CONFIG` ei kelpaa
asetukseksi** — ESPHome hyväksyy vain NONE, ERROR, WARN, INFO, DEBUG, VERBOSE
ja VERY_VERBOSE. DEBUG on matalin taso joka näyttää vedoksen, ja sen voi laskea
INFO:on kun osoitteet on vahvistettu.

**Osoitteet ovat jo konfiguraatiossa.** Ne on laskettu vanhan OWFS-kartan
osoitteista eikä luettu väylältä, joten
[`discovery.yaml`](discovery.yaml) on nyt varalla oleva työkalu eikä
välttämätön vaihe: sitä tarvitaan vain jos jokin laskettu osoite ei vastaa
mitään.

**Käynnistä uudelleen pari kertaa ja vertaa luetteloa.** Yksi onnistunut
luettelo ei todista mitään: tähtitopologian vika on nimenomaan se että osa
antureista löytyy ja osa ei, ja löytyneet vaihtuvat ajojen välillä. **Sama
luettelo kolmesti tarkoittaa että topologia ei ole tässä verkossa ongelma** —
ja koska verkko on toiminut Raspberryllä, odotus on että se ei ole.

**Älä laske lokitasoa INFO:on.** Osoiteluettelo tulostuu CONFIG-tason
vedoksessa, ja INFO vaientaa juuri sen rivin jota ollaan hakemassa — tuloste
näyttää silloin siltä ettei antureita löytynyt lainkaan. Sama mekanismi piilotti
solmun IP-osoitteen stiebelin käyttöönotossa ja maksoi siellä yhden kierroksen.

**Yksi isäntä kerrallaan.** Jos Raspberry on kiinni, C3 ei saa olla — eikä
toisinpäin. Jatkoholkki pakottaa tämän fyysisesti.

## Jos mitään ei löydy

Järjestyksessä, halvimmasta ylöspäin:

| Epäilty | Testi |
|---|---|
| DQ ja VDD ristissä | vaihda ne keskenään ja käynnistä uudelleen |
| ylösveto puuttuu tai on väärässä paikassa | mittaa: DQ:n pitäisi levätä 3,3 V:ssa |
| maa ei ole maa | palaa mittaukseen 2 |
| koko haara irti keskipisteessä | kokeile yhtä haaraa kerrallaan |

Jos yksittäinen haara toimii mutta kaikki yhdessä eivät, vika on topologiassa
eikä kytkennässä — ja korjaus on haaroittaa tähti omille nastoilleen. Se on
`one_wire`-komponentissa pelkkä toinen merkintä eri nastalla, ks.
[CLAUDE.md](CLAUDE.md).

## Osoitteesta sijainniksi

Osoite on pysyvä ja yksilöllinen mutta se ei kerro sijainnista mitään.
Kartoitus tehdään menetelmällä joka on tässä repossa todettu vahvimmaksi:
**muuta yhtä asiaa ja katso väylää.** Lämmitä yksi anturi kädellä ja katso mikä
osoite liikkuu. Kymmenen sekuntia per anturi, eikä jälkikäteen jää mitään
tulkittavaa.

Jos anturit ovat seinän sisässä eikä niihin pääse käsiksi, kartoitus tapahtuu
lämmityksen kautta ja on hitaampi — mutta se on silti sama menetelmä.

**Kirjaa pari heti kun se on todettu.** Ilman sitä konfiguraatio on lista
heksalukuja joiden merkitys on yhden ihmisen muistissa.

## Rauta

**ESP32-C3 SuperMini**, ja peruste on varastosta eikä tekniikasta: C3:ita on
kuusi, joista kaksi on ilman varausta. Vapaat D1 minit ovat aidonin
vakuutus — se on repon ainoa käynnissä oleva tuotantojärjestelmä eikä sille ole
varalevyä, ja HAN-portin virtabudjetti sulkee ESP32:n siitä pois.

Tekninen puoli tukee samaa valintaa kahdella perusteella, jotka molemmat ovat
merkityksellisiä vasta jos antureita on paljon: enemmän muistia entiteeteille ja
vakaampi keskeytyskäsittely bittiä heiluttavalle ajoitukselle. Ks.
[CLAUDE.md](CLAUDE.md).

**Osaostoja ei ole.** Yksi vastus ja levy hyllystä.

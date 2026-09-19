# CLAUDE.md — talon 1-Wire-väylä

> **Tekniset tiedot ja perustelut.** Yleiskuva: [README.md](README.md).

## Lähtötilanne

Talossa on olemassa oleva 1-Wire-verkko jossa on DS18B20-antureita. Verkko ei
ole käytössä. Anturimäärä, sijainnit ja käytöstäpoiston syy ovat kaikki
selvittämättä — kaikki kolme selviävät samalla kertaa kun väylälle kytketään
isäntä.

**Topologia on tähti**, ja se on tämän projektin ainoa tunnettu tekninen riski.

## Miksi tähti on ongelma, ja milloin se ei ole

1-Wire on määritelty **ketjuksi**: yksi runko, lyhyet tynkät. Tähdessä jokainen
haara on pitkä tynkä, ja haarapisteestä syntyy heijastuksia jotka summautuvat
takaisin väylälle kesken aikakriittisen aikavälin. Maximin omissa
sovellusohjeissa tähti on nimetty yleisimmäksi syyksi epäluotettavaan
1-Wire-verkkoon.

**Vika ei ole selvä vaan epämääräinen**, ja se on pahempaa: osa antureista
löytyy ja osa ei, löytyneet katoavat lämpötilan mukaan, ja CRC-virheitä tulee
satunnaisesti. Oire näyttää anturivialta vaikka syy on aaltomuoto.

Kolme korjausta, halvimmasta ylöspäin:

1. **Haaroita se GPIO:ille.** Jos tähti kerääntyy yhteen pisteeseen, jokainen
   haara voi saada oman nastansa ja oman väyläinstanssinsa. Silloin tähteä ei
   ole. Tämä on ilmainen ja poistaa koko ongelmaluokan — mutta se edellyttää
   että keskipiste on fyysisesti käsillä ja että haaroja on vähemmän kuin
   vapaita nastoja.
2. **Aktiivinen ylösveto.** DS2482-100 on I²C-silta jossa on kunnollinen
   ajokyky ja ohjattu nousuaika. Se on vakiintunut korjaus marginaaliseen
   verkkoon. Kovempi passiivinen ylösvetovastus ei ole — se parantaa nousuaikaa
   mutta kasvattaa virtaa eikä tee mitään heijastuksille.
3. **Verkon uudelleenvetäminen ketjuksi.** Kallein ja epätodennäköisin.

**Tässä projektissa väylä pidetään yhtenä**, koska haaroittamiselle ei ole
tarvetta ennen kuin epäluotettavuutta on havaittu. Jos ensimmäinen kartoitusajo
löytää kaikki anturit vakaasti, topologia ei ole ongelma tässä verkossa.

## Sähköinen kytkentä

| | |
|---|---|
| Data | GPIO, **4,7 kΩ ylösveto 3,3 V:iin** |
| Syöttö | **kolme johdinta, ei loiskäyttöä** |
| Jännite | DS18B20 toimii 3,0–5,5 V:lla, eli 3,3 V käy suoraan |

**Loiskäyttö on toinen klassinen syy hajoaviin 1-Wire-verkkoihin.**
Parasiittisessä kytkennässä anturi ottaa käyttöjännitteensä datalinjasta ja
lataa sisäisen kondensaattorinsa väylän ollessa ylhäällä. Lämpötilamuunnos vetää
1,5 mA, ja pitkässä verkossa jossa on monta anturia se ei riitä — muunnokset
epäonnistuvat juuri silloin kun antureita on eniten. Kolmella johtimella sitä
ongelmaa ei ole.

Jos verkko on vedetty Cat5e:llä, johtimia on kahdeksan eikä kolmen käyttäminen
maksa mitään.

## Levyvalinta

**ESP32-C3 SuperMini.**

Ensisijainen peruste on varasto: C3:ita on kuusi, joista stiebelin solmu vei
yhden ja lattialämmityksen suunnitelma varaa kolme. Kaksi on ilman varausta.

**Vapaat D1 minit eivät ole vapaita.** Ne ovat aidonin vakuutus. Aidon on repon
ainoa käynnissä oleva tuotantojärjestelmä, ja se on ainoa projekti jossa
ESP8266 ei ole makuasia vaan pakko — HAN-portin 280 mA:n virtabudjetti sulkee
ESP32:n pois. Jos sen levy hajoaa, tilalle tarvitaan D1 mini samana päivänä.

Tekniikka tukee samaa valintaa kahdesta suunnasta, ja molemmat merkitsevät
vasta jos antureita on paljon:

- **Muisti.** Jokainen anturi on entiteetti. Stiebelin solmulla mitattuna
  viisikymmentä entiteettiä maksoi 3,8 kt RAMia — C3:lla se on alle kaksi
  prosenttia, ESP8266:lla se olisi kahdeksasosa kaikesta vapaasta.
- **Ajoitus.** 1-Wire on bittiä heiluttava protokolla jonka aikaikkunat ovat
  mikrosekunteja, ja aikakriittiset jaksot ajetaan keskeytykset pois kytkettynä.
  ESP8266:lla WiFi-pino kilpailee samasta ajasta, ja se näkyy CRC-virheinä
  pitkällä väylällä. Tämä ei ole este ESP8266:lle — moni ajaa DS18B20:ia sillä
  ongelmitta — mutta se on riski jota ei tarvitse ottaa.

**Valinta ei ole lopullinen ennen kuin anturimäärä on tiedossa.** Kartoitusajon
voi tehdä millä tahansa hyllyssä olevalla levyllä, koska se on kertakäyttöinen
konfiguraatio eikä varaa mitään.

## ESPHomen komponentit

ESPHome jakaa tämän kahteen: **väylä** ja **anturi**.

```yaml
one_wire:
  - platform: gpio
    pin: GPIO4
    id: bus_a

sensor:
  - platform: dallas_temp
    one_wire_id: bus_a
    address: 0x1234567890abcdef
    name: "..."
```

Vanhempi `dallas:`-komponentti teki molemmat yhdessä lohkossa. Jaon jälkeen
useita väyliä voi määritellä rinnakkain eri nastoihin, mikä on juuri se mitä
tähden haaroittaminen vaatisi.

**Osoitteeton väylä luetteloi löytämänsä.** Kartoitusajossa ei määritellä
yhtäkään sensoria; komponentti tulostaa löytyneet ROM-osoitteet
käynnistysvedoksessa.

## RJ45:n nastajärjestys, ja mitä siitä voi päätellä

Verkko päättyy RJ45:een. **Data ja paluu ovat nastat 4 ja 5** — sininen pari —
ja sille on mekaaninen peruste eikä pelkkä tapa.

DS9490R kantaa 1-Wiren RJ11-liittimessään nastoissa 3 ja 4
([datalehti](https://www.analog.com/media/en/technical-documentation/data-sheets/ds9490-ds9490r.pdf)).
RJ11 on kuusipaikkainen ja kapeampi kuin RJ45, ja pistoke istuu rasian
keskelle: sen nastat 1–6 osuvat kahdeksanpaikkaisen rasian nastoihin 2–7.
RJ11:n nasta 3 on siis RJ45:n nasta 4, ja RJ11:n nasta 4 on RJ45:n nasta 5.

Verkko jota on ajettu DS9490:llä noudattaa siis tätä, riippumatta siitä mitä
asentaja ajatteli tekevänsä — pistoke määräsi sen.

**Syöttö on eri asia.** VDD ei ole vakiintunut mihinkään nastaan: yleisiä ovat
1, 2 ja 6. Se mitataan eikä päätellä, ja se on ainoa kohta tässä projektissa
jossa virhe tuhoaa antureita sen sijaan että jättäisi väylän hiljaiseksi.

**Mutta tässä verkossa syöttö on jo vedetty**, koska sitä on ajettu myös
Raspberryn GPIO:sta kolmella johtimella. Se ratkaisee kolme asiaa kerralla:

- **Kaksi jännitetasoa, ei yhtä.** Tässä luki hetken että verkko on 3,3 voltin
  verkko koska Raspberry ajaa sitä. Se oli väärin: **syöttö on 5 V ja ylösveto
  3,3 V.** Ks. nastataulukko alla.
- **Tähti toimii tässä talossa.** Jos Raspberry luki verkkoa, topologia ei ole
  ollut este. Kysymys *miksi verkko ei ole käytössä* siirtyy siihen että isäntä
  poistui, ei siihen että verkko petti.
- **Vanha kaapeli on dokumentaatio.** Jos se löytyy, siitä lukee syöttöjohdin
  suoraan eikä mitään tarvitse päätellä konventioista.

### Vanha toteutus: värit eivät kerro mitään

**Tässä tiedostossa luki hetken että johdinvärit ovat DS18B20:n vakiovärit ja
että uuden kaapelin voi tehdä niiden mukaan. Se oli väärin.** Kaapeli on se
joka sattui olemaan käsillä kun vanha toteutus tehtiin, eikä mustalla,
punaisella tai keltaisella ole tässä asennuksessa mitään sovittua merkitystä.

Väite oli uskottava, koska juuri nuo kolme väriä ovat vedenkestävän
DS18B20-sauvan vakiovärit. Se on sama virhemuoto joka on tässä repossa
kirjattu MCP2515:n terminaattorista: **merkintä ehdottaa, mittari ratkaisee.**
Siellä `121` oli painettu kortille eikä se silti yltänyt väylälle; täällä väri
näyttää koodilta eikä se ole koodi.

Mitä valokuvasta jää voimaan:

- **Kolme johdinta kahdeksasta paikasta** on käytössä
- **Ylösveto on isännän päässä**, juotettuna Raspberryn riman kahden nastan
  väliin — verkossa itsessään ei ole ylösvetoa
- Verkko on **3,3 voltin verkko**, koska Raspberry ajaa sitä

Mikä johdin on mikä, on kokonaan avoin.

### Lopullinen nastakartta, luettuna pistokkeesta

Kaikki päättely päättyy tähän, ja tämä on luettu eikä pääteltyä:

| RJ45 | Johdin | Signaali | Raspberryn rima | Pari |
|---|---|---|---|---|
| **1** | musta | GND | 6 tai 9 | oranssi |
| **2** | punainen | **5 V** | 2 | oranssi |
| 3 | — | — | — | |
| **4** | keltainen | **data** | 7 (GPIO4) | sininen |
| **5** | valkoinen | GND | 6 tai 9 | sininen |
| 6–8 | — | — | — | |

**Parisuus toteutuu molemmissa pareissa.** Data ja sen maa ovat sinisessä
parissa, syöttö ja sen maa oranssissa. Kumpikin signaali kulkee oman
paluujohtimensa kanssa samassa kierteessä.

**Neljä toisistaan riippumatonta reittiä päätyi samaan tulokseen:** DS9490:n
RJ11-pistokkeen fyysinen ulottuvuus rasian keskimmäisiin nastoihin,
parisuusperiaate, Raspberryn riman nastat ja lopulta pistokkeen suora luenta.
Yksikään ei nojaa toiseen, ja ne kaikki sanovat että data on nastassa 4.

Nastassa 3 ei ole johdinta. Riman puolella on viides juotospiste nastassa 1
(3,3 V), jossa on vastuksen toinen pää eikä johdinta — 3,3 V:a ei viedä
verkkoon.

### Riman nastat, luettuina

Kuvista ja käyttäjän vahvistuksesta yhdessä:

| Nasta | Signaali | Johdin |
|---|---|---|
| 1 | 3,3 V | **vain vastus**, ei johdinta |
| 2 | **5 V** | punainen |
| 6 | GND | musta tai valkoinen |
| 7 | GPIO4, data | **keltainen** |
| 9 | GND | toinen niistä |

**Syöttö on 5 V ja ylösveto 3,3 V**, eikä se ole epäjohdonmukaisuus vaan hyvä
suunnittelu. Anturit saavat täyden jännitteen pitkälle vedolle, mutta koska
DS18B20:n datanasta on avokollektori, **ylätason määrää yksin ylösveto** — ja
3,3 V:iin vedettynä datalinja on turvallinen 3,3 voltin mikro-ohjaimelle.
Raspberryn GPIO4 on selvinnyt vuosia juuri siksi.

Se selittää myös nastan 1 paljaan juotospisteen: siinä on vastuksen toinen pää
eikä johdinta, koska 3,3 V:a ei viedä verkkoon lainkaan.

**Neljäs johdin on toinen maa.** Kaksi maata ja yksi syöttö ja yksi data — ei
mitään tuntematonta. Kumpi maadoitusjohdin on kummassa nastassa on
yhdentekevää.

### Maat ovat rinnan, eivät erillisiä

Ne yhdistyvät **molemmissa päissä**. Raspberryn nastat 6 ja 9 ovat saman
maatason nastoja, ja DS18B20:ssä on yksi GND-nasta — mikä tahansa maa joka
anturille tulee, on siinä samassa solmussa. Sama koskee jokaista verkon
laitetta.

Kaksi maajohdinta ovat siis **rinnakkaisia vastuksia kahden saman pisteen
välillä**, eivät toisistaan erotettuja paluuteitä. Se tarkentaa parisuuden
hyödyn: virta jakautuu johtimien kesken resistanssin suhteessa eikä sen mukaan
kumpi on signaalin "oma" pari.

Todellinen hyöty tärkeysjärjestyksessä:

1. **Puolittunut paluuresistanssi.** Kiistaton, ja merkitsee pitkällä vedolla
   jossa parinkymmenen anturin yhteisvirta kulkee paluujohtimissa.
   Lämpötilamuunnos vetää noin 1,5 mA per anturi.
2. **Vierekkäisyys datan kanssa.** Reaalinen mutta pienempi kuin miltä
   parisuusargumentti kuulostaa — 1-Wiren reunat ovat mikrosekunteja, joten
   induktiivinen kytkeytyminen ei ole hallitseva ilmiö. Resistanssi ja
   kapasitanssi ovat.
3. **Vikasietoisuus.** Toisen maajohtimen katketessa verkko toimii silti.

### Kytkentäohje uuteen kaapeliin

- **Kytke molemmat maat.** Ei siksi että ne olisivat eri asioita vaan siksi
  että ne ovat rinnan. Jos vain toinen tulee kytketyksi, mikään ei rikkoudu —
  ja **juuri siksi virhe jäisi huomaamatta**, kunnes pitkän vedon jännitehäviö
  alkaisi oireilla kaukaisimmalla anturilla.
- **Älä hajota pareja.** Pidä data ja sen maa samassa kierretyssä parissa ja
  syöttö ja sen maa toisessa. Jos data ja syöttö päätyvät samaan pariin,
  kaapeli näyttää ulospäin samalta mutta menettää sen ominaisuuden jonka takia
  parit ovat olemassa. Vanhassa asennuksessa data ja paluu ovat RJ45:n
  nastoissa 4 ja 5 eli **sinisessä parissa** — sama mihin DS9490:n toimiminen
  johti aivan eri päättelyä myöten.
- **Ylösveto ei mene verkkoon.** Se on C3:n päässä GPIO4:n ja 3V3:n välissä, ja
  verkkoon lähtee vain neljä johdinta.

### Kaapeli tehdään tehdaspistokkeesta, eikä vanhaa pureta

Uusi kaapeli syntyy **valmiista patch-kaapelista jonka toinen pää leikataan
irti**. Tehdaspuristus jää rasian päähän ja neljä johdinta juotetaan C3:n
rimaan. Kaksi asiaa seuraa siitä, ja kumpikin on parempi kuin siirtovaihtoehto:

- **Palautus on pistokkeen vaihto, ei juotostyö.** Raspberryn kaapeli jää
  ehjänä paikalleen, joten vanhan toteutuksen palauttaminen on kahden sekunnin
  operaatio. Se on sama etu jonka jatkoholkki tarjoaisi, ilman holkkia — ja se
  on se ominaisuus joka siirtosuunnitelmassa menetettiin.
- **Rasian puoleinen liitos ei ole itse tehty.** Puristus on se kohta jossa
  käsityö tyypillisimmin pettää, ja tässä se ohitetaan kokonaan.

**Yksi isäntä kerrallaan säilyy fyysisenä pakkona.** Kummallakin kaapelilla on
oma pistokkeensa mutta verkolla vain yksi paikka, joten molemmat eivät mahdu
kiinni yhtä aikaa. Sääntö ei jää muistin varaan.

#### Johtimet valitaan nastanumerolla, ei värillä

Patch-kaapeli on suora, eli nasta N yhdessä päässä on nasta N toisessa.
Tarvittavat neljä ovat siis nastat 1, 2, 4 ja 5 riippumatta siitä miltä ne
näyttävät.

**Sininen pari on nastoissa 4 ja 5 sekä T568A:ssa että T568B:ssä**, joten
datapari on väriltäänkin varma. Nastat 1 ja 2 sen sijaan ovat B:llä oranssi
pari ja A:lla vihreä. Kaapelin standardin erottaa reunimmaisesta johtimesta:
oranssi tarkoittaa B:tä, vihreä A:ta.

Parisuus toteutuu automaattisesti kummassakin, koska nastat 1–2 ja 4–5 ovat
pareja molemmissa standardeissa. **Parisuus ei siis ole kiinni standardista
lainkaan — vain värinimet ovat.**

Jatkuvuusmittaus kuoritusta johtimesta pistokkeen nastaan ohittaa koko
kysymyksen ja kattaa samalla sen epätodennäköisen tapauksen että kaapeli on
ristiin kytketty. Tässä talossa väri ei ole ollut kertaakaan luotettava viite.

Neljä käyttämätöntä johdinta katkaistaan eri mittaan tai eristetään.

#### Isännän pätkä pidetään lyhyenä

Kaapelista ei tehdä pitkää. **Isännän ja rasian väli on ainoa segmentti joka on
sarjassa koko tähden kanssa** — haaraan lisätty metri koskee sen haaran
antureita, tähän lisätty metri lisätään jokaisen 25 laitteen matkaan yhtä aikaa.

Kapasitanssi on se joka maksaa: Cat5 on noin 50 pF/m, joten kymmenen metriä
tuo 500 pF lisää 4,7 kΩ:n ylösvedon kuormaksi. Nousuaika on silloin jo
mikrosekunteja, ja 1-Wiren lukuikkuna on ~15 µs putoavasta reunasta. Marginaali
kuluu ennen kuin yhtäkään haaraa on otettu mukaan — ja tähti on jo valmiiksi
topologioista vaikein.

Ainoa todellinen syy viedä C3 kauas rasiasta on pistorasian tai kentän puute,
ja kumpikin ratkeaa halvemmalla:

- **Virta:** pitkä USB-kaapeli. Metrit USB:n puolella eivät maksa väylälle
  mitään. Siirrä virtaongelma, älä väyläongelmaa.
- **Kenttä:** mitattava ennen kuin kaapeli leikataan. `Wi-Fi`-anturi on
  konfiguraatiossa juuri tätä varten. Jos kenttä on huono, oikea korjaus on
  silti pitää C3 keskittimellä ja korjata radio — ulkoinen antenni tai toistin.
  **Radion voi korjata jälkikäteen, väylän kapasitanssia ei.**

### C3 toistaa saman

Värit ovat T568B:n mukaiset; A:lla oranssin tilalla on vihreä.

| C3 | RJ45-nasta | Johdin |
|---|---|---|
| **5V** | 2 | oranssi |
| **GND** | 1 ja 5 | valko-oranssi ja valkosininen |
| **GPIO4** | 4 | sininen |
| **4,7 kΩ GPIO4:stä 3V3:een** | — | ei verkkoon |

SuperMinin 5V-nasta on USB:n VBUS:issa, joten se antaa saman viisi volttia kuin
Raspberry. **Ylösveto menee 3V3:een eikä viiteen** — se on tämän kytkennän
ainoa kohta jossa virhe tuhoaa GPIO:n, ja se on sama virhe jonka Raspberry
välttää.

Vaihtoehto olisi syöttää verkko 3,3 voltista, jolloin kaikki olisi yhdellä
tasolla. Sitä ei tehdä: **5 V on se mikä on todistetusti toiminut tässä
talossa**, ja pitkällä vedolla sen jännitehäviövara on merkitsevä. Yhden tason
siisteys ei ole sen arvoinen.

### Päättelyketju RJ45:een asti

Kaksi vahvistettua asiaa vievät päättelyn molempiin päihin asti, ja ketju on
tässä auki niin että sen voi kumota jos jokin premissi pettää.

**Premissi 1: Raspberryn kytkentä on se yleinen malli.** Kolme johdinta
nastoihin 1, 7 ja 9 — kaikki parittomassa rivissä vieretysten — ja ylösveto
nastasta 1 nastaan 7.

| Rima | Merkitys |
|---|---|
| 1 | VDD, 3,3 V |
| 7 | DQ, GPIO4 |
| 9 | GND |

Valokuva tukee tätä: vastus ylittää muutaman nastavälin **saman rivin sisällä**.
Jos syöttö olisi nastassa 17, joka on toinen 3,3 V, vastus olisi selvästi
pidempi. Riman päätä ei näy kuvassa, joten absoluuttista numerointia ei voi
siitä laskea — mutta pituus sopii.

**Premissi 2: DS9490 on toiminut tässä verkossa.** Tämä on vahvempi kuin mikään
konventio, koska se on toiminnallinen vaatimus eikä tapa. Sovittimen RJ11-liitin
kantaa 1-Wiren nastoissa 3 ja 4, ja RJ11-pistoke istuu RJ45-rasian keskelle
niin että sen nastat osuvat rasian nastoihin 2–7. **Jos sovitin on toiminut,
data ja paluu ovat RJ45:n nastoissa 4 ja 5** — muualla ne eivät olisi
sovittimen ulottuvilla lainkaan.

Suunta seuraa samasta: RJ11:n nasta 3 on data ja se osuu RJ45:n nastaan 4;
RJ11:n nasta 4 on paluu ja se osuu nastaan 5.

**Johtopäätös:**

| Signaali | RJ45 | Rima | Varmuus |
|---|---|---|---|
| DQ | **4** | 7 | päätelty kahdesta premissistä |
| GND | **5** | 9 | päätelty kahdesta premissistä |
| VDD | **kolmas käytössä oleva paikka** | 1 | luettavissa pistokkeesta silmällä |

Syöttöjohdin ei seuraa kummastakaan premissistä, koska DS9490 ei käytä sitä
eikä RJ45:n syötölle ole vakiintunutta paikkaa. **Mutta pistokkeessa on kolme
johdinta kahdeksasta paikasta**, ja kun kaksi niistä on nastat 4 ja 5, kolmas
on se mikä jää. Sen näkee katsomalla, ei mittaamalla.

**Premissi 2 on todettu kolmesti, ei kerran.** Sovitin on toiminut suoraan
väylään kytkettynä, **rasian läpi** ja **RJ45-jatkoholkin läpi**. Holkki on
nasta nastaan eikä siirrä mitään, ja rasian läpi toimiminen tarkoittaa että
rasian johdotus säilyttää ne keskimmäiset paikat joihin RJ11-pistoke fyysisesti
ylettyy. Se sulkee pois sen vaihtoehdon että jokin välikappale olisi siirtänyt
nastoja.

**Mikä kumoaisi tämän vielä.** Vain premissi 1: jos Raspberryn kytkentä poikkeaa
yleisestä mallista — esimerkiksi `dtoverlay=w1-gpio,gpiopin=17` — data ei ole
nastassa 7. Se näkyy `/boot/firmware/config.txt`:stä, eikä se muuta RJ45:n
puolta vaan sen mitä vastaan mittaus tehdään.

### Jatkoholkki on myös kytkentätapa

Se että sovitin toimii holkin läpi ei ole pelkkä todiste vaan käyttökelpoinen
tapa liittää uusi isäntä: **lyhyt punoskaapeli C3:lta RJ45-pistokkeeseen ja
siitä holkin kautta verkkoon.** Rasiaa ei tarvitse avata eikä muuttaa.

Kaksi etua seuraa samasta:

- **Vaihto on kahden sekunnin operaatio.** Raspberryn pistoke ulos, C3:n
  pistoke sisään — ja koska holkissa on vain yksi paikka kummallekin puolelle,
  se myös **pakottaa yhden isännän kerrallaan** fyysisesti. Se sääntö ei jää
  muistin varaan.
- **Paluutie on olemassa.** Jos C3 osoittautuu huonommaksi, vanha toteutus on
  yhden pistokkeen päässä.

**Tämä ei korvaa mittausta vaan tekee siitä tarkistuksen.** Kolme
jatkuvuusmittausta joko vahvistavat taulukon tai kumoavat sen, ja kumpikin
lopputulos kestää viisi minuuttia.

### Vanha kaapeli on mittalaite

Johtimet tunnistetaan mittaamalla, ja vanha kaapeli tekee siitä helppoa: sen
toisessa päässä on Raspberryn rima, jonka nastojen merkitys on tiedossa.

Jatkuvuus RJ45-pistokkeen nastoista riman nastoihin antaa taulukon suoraan:

| Rima | Merkitys | ⇒ RJ45-nasta |
|---|---|---|
| 7 (GPIO4) | DQ | mitattava |
| 1 | VDD, 3,3 V | mitattava |
| 6 | GND | mitattava |

**Tarkista `dtoverlay`-rivi ennen kuin luotat nastaan 7.** Jos
`/boot/firmware/config.txt` sanoo `dtoverlay=w1-gpio,gpiopin=17` tai vastaavaa,
data on muualla kuin GPIO4:ssä. Se tiedosto on dokumentaatio siinä missä
kaapelikin.

Kun taulukko on täytetty, uusi kaapeli tehdään **paikkojen mukaan** — väri saa
olla mikä tahansa, kunhan RJ45:n nasta menee oikeaan nastaan C3:lla.

### Ylösveto voi olla jo paikallaan

Raspberryn `w1-gpio` vaatii ulkoisen 4,7 kΩ:n. Jos se on aikanaan asennettu
keskipisteeseen tai kaapeliin Raspberryn pään sijaan, **se on yhä siellä** — ja
toinen ylösveto C3:lla laittaisi ne rinnan, jolloin yhteisvastus olisi 2,35 kΩ.
Se ei riko mitään, mutta se ei ole tarkoitus eikä sitä huomaa mistään.

Yksi mittaus ennen kuin vastusta juotetaan mihinkään, kaikki jännitteet pois:

| DQ ↔ VDD | Päätelmä |
|---|---|
| ~4,7 kΩ | ylösveto on jo verkossa — älä lisää toista |
| avoin | se oli Raspberryn päässä — lisää omasi |

**Valokuvien perusteella jälkimmäinen pätee**, eli C3 tarvitsee oman
ylösvetonsa. Mittaus jää silti listalle, koska se maksaa kymmenen sekuntia ja
koska valokuva kertoo mitä yhdessä päässä on — ei sitä mitä keskipisteessä voi
olla.

Tästä seuraa menettely joka rajaa riskin nollaan: **todenna data ja paluu
kahdella johtimella ennen kuin kytket kolmannen.** DS9490 ajaa väylää
loiskäytöllä eikä anna syöttöä, joten se luetteloi koko verkon ilman että VDD:tä
tarvitsee arvata. Jos anturit löytyvät nastoilla 4 ja 5, ne kaksi ovat oikein —
ja vasta sitten etsitään syöttöjohdin.

## Kaksi isäntää ei käy

Ytimen `ds2490`-ajuri ja ESPHomen `one_wire` ovat molemmat isäntiä. **Vain
toinen saa olla kiinni kerrallaan**, ja tämä koskee myös vanhaa syöttöä tai
unohtunutta sovitinta jossain toisessa päässä — siksi verkon jännite mitataan
ennen kuin siihen kytketään mitään.

Linuxissa sama koskee OWFS:ää ja ytimen ajuria keskenään: jos `owserver` on
ajossa, se varaa sovittimen eikä `/sys/bus/w1/devices/` täyty.

## Kaksi ansaa jotka on jo maksettu muualla

**Lokitaso.** Osoiteluettelo on CONFIG-tason viesti. `level: INFO` vaientaa sen,
ja tuloste näyttää silloin siltä ettei antureita löytynyt. Sama mekanismi
piilotti stiebelin solmun IP-osoitteen — ks.
[`../stiebel.eltron/CLAUDE.md`](../stiebel.eltron/CLAUDE.md), "Bringing the C3
up".

**Osoite ei ole sijainti.** 64-bittinen ROM-osoite on pysyvä ja yksilöllinen,
eikä se kerro mitään siitä missä anturi on. Kartoitus tehdään lämmittämällä
yksi anturi kerrallaan ja katsomalla mikä osoite liikkuu. Se on sama
todistelaji jonka stiebelin työ totesi vahvimmaksi: muuta yhtä asiaa ja katso
väylää, kymmenen sekuntia eikä mitään tulkittavaa jälkikäteen.

Kirjaa osoite ja sijainti pariksi heti kun se on todettu. Ilman sitä
konfiguraatio on lista heksalukuja joiden merkitys on yhden ihmisen muistissa.

## Palautettu inventaario: 25 laitetta nimettynä

Vanhan Raspberryn levyltä löytyi OWFS-pohjainen toteutus vuosilta 2015–2020, ja
siinä oli **valmis laitekartta**. Se korvaa koko sen kartoitustyön jota tämä
tiedosto suunnitteli: osoitteet ovat nimettyinä huoneisiin ja asemiin.

### 19 lämpötila-anturia

| Osoite (OWFS) | Sijainti |
|---|---|
| `28.FF265A750400` | K ikkuna sisä |
| `28.FF897B750400` | K ikkuna ulko |
| `28.FFD0354C0400` | K sisä |
| `28.FF94134D0400` | K sisä ovi katto |
| `28.FF632E4E0400` | KHH sisä ovi katto |
| `28.1EF457050000` | MH1 etelä sisä |
| `28.58EF57050000` | MH1 länsi (piha) |
| `28.FF12204E0400` | MH1 sisä ovi katto |
| `28.FF5F18730400` | MH2 itä |
| `28.FF7F35740400` | MH3 itä |
| `28.FFEC79760400` | MH3 pohjoinen |
| `28.65E657050000` | MH4 länsi (piha) |
| `28.785317060000` | MH4 pohjoinen sisä |
| `28.799CF6050000` | MH4 pohjoinen ulko |
| `28.FFBA7B760400` | OH sisä |
| `28.FFD4324C0400` | OH sisä ovi katto |
| `28.FF807B750400` | OH ulko |
| `28.FF4E78760400` | VH etelä sisä |
| `28.FF8276750400` | VH etelä ulko |

### Ja kuusi muuta laitetta

| Osoite | Piiri | Mitä |
|---|---|---|
| `26.139121010000` | DS2438 | lämpötila **ja kosteus**, tekninen tila |
| `12.BC37B6000000` | DS2406 | `latch.B`, varasto |
| `12.A82DB6000000` | DS2406 | `latch.B`, varasto |
| `12.892EB6000000` | DS2406 | `latch.B`, varasto |
| `12.372EB6000000` | DS2406 | `latch.B`, varasto |
| `12.2E30B6000000` | DS2406 | `latch.B`, varasto |

### Mitä nimet kertovat

**Nämä ovat rakenneantureita, eivät huoneilman antureita.** Nimissä toistuu
pari *sisä* ja *ulko* samassa paikassa — "K ikkuna sisä" ja "K ikkuna ulko",
"OH sisä" ja "OH ulko" — ja vanhan toteutuksen tageissa esiintyy *väliseinä*.
Anturit on siis asennettu mittaamaan rakenteen lämpötilaa kahdelta puolelta,
tyypillisesti ikkunan tai oven kohdalta, ja osa katonrajaan.

Kolme seurausta:

- **Lattialämmityksen jakotukkisuunnitelma ei muutu.** Nämä eivät ole valussa,
  joten ne eivät korvaa stiebelin 25 anturin asennusta. Se kysymys on nyt
  suljettu — ks. alla.
- **Kosteusmittaus on jo olemassa** teknisessä tilassa, DS2438:lla. Repon
  suunnitelmassa kaksi BME280:aa odottaa huoneisiin; tämä ei korvaa niitä,
  mutta se kannattaa tietää ennen kuin niille etsitään paikkaa.
- **Viisi kytkintuloa varastossa on selvittämättä.** `latch.B` on DS2406:n
  digitaalitulo, ja mitä ne siellä valvovat ei käy nimestä ilmi.

### Mitä väylällä voi vielä olla

Kartta on vuodelta 2020 ja verkko on kasvanut kerran jo sitä ennen. Kaksi
laiteryhmää tiedetään puuttuvan siitä:

- **Sauna.** Ei kummassakaan lähteessä, vaikka se on ainoa tila jonka
  odottaisi olevan mukana.
- **Leivinuunin anturit.** Näitä ei voi olla DS18B20:llä: **sen yläraja on
  +125 °C** ja leivinuuni käy 200–400 asteessa. Todennäköisin vaihtoehto
  1-Wire-väylällä on **MAX31850**, joka lukee K-tyypin termoparia
  1-Wire-rajapinnan takaa — piiri pysyy viileässä ja vain termopari on
  kuumuudessa. Perhekoodi `3B`.

**Perhekoodi kertoo laitetyypin suoraan käynnistysluettelosta**, joten
ensimmäinen käynnistys ei kerro vain montako laitetta väylällä on vaan myös
mitä ne ovat:

| Perhekoodi | Piiri | Mitä |
|---|---|---|
| `28` | DS18B20 | lämpötila |
| `10` | DS18S20 | lämpötila, vanhempi polvi |
| `3B` | MAX31850 | termopari, korkea lämpötila |
| `26` | DS2438 | lämpötila ja kosteus |
| `12` | DS2406 | kytkintulo |
| `81` | DS2490 | sovitin itse, ei anturi |

### ESPHome ei lue kaikkea tätä

`dallas_temp` kattaa DS18B20:n ja DS18S20:n, eli **ne 20 lämpötila-anturia**.
**DS2438, DS2406 ja MAX31850 eivät ole ESPHomen omissa komponenteissa**, joten
kosteus, viisi kytkintuloa ja mahdolliset uunianturit jäisivät lukematta. Tämä
on tarkistettava asennetusta versiosta ennen kuin siihen nojaa, mutta suunta on
selvä: jos ne halutaan mukaan, tarvitaan OWFS rinnalle tai tilalle.

**Rajoite ei ole ESP32 vaan ESPHomen komponenttivalikoima**, ja se ero on
olennainen. Sähköisesti ja protokollatasolla kaikki 1-Wire-laitteet ovat samalla
väylällä samanarvoisia: sama ajoitus, sama ROM-haku, sama isäntä. Ero on vain
siinä mitä komentoja laitteelle lähetetään ja miten vastaus tulkitaan — ja se on
ohjelmistoa.

Kolme tapaa saada loput samalle C3:lle:

- **Ulkoinen komponentti.** `external_components` hakee koodin gitistä, ja tämä
  repo käyttää sitä jo: aidon ajaa `psvanstrom/esphome-p1reader`-komponenttia.
  Jos jollekin näistä piireistä on valmis komponentti, se on yhden lohkon
  lisäys — ja silloin **muista kiinnittää `ref:`**, samasta syystä kuin
  aidonissa.

  **Latcheille sellainen on olemassa, ja se on kirjattava tänne koska sitä ei
  löydä hakemalla.** Katso alempi luku.
- **Oma komponentti tai lambda.** `one_wire`-väylä tarjoaa C++-rajapinnan, jota
  voi ajaa omasta koodista. DS2406:n kytkintulo on näistä yksinkertaisin; DS2438
  työläin, koska siinä on useita sivuja ja CRC per sivu.

  **MAX31850 ei enää kuulu tähän listaan.** `dallas_temp` lukee sen sellaisenaan,
  koska se ei tarkista perhekoodia ja koska piirin rekisteriformaatti osuu samaan
  1/16 °C:n asteikkoon. Se on todettu mittaamalla, ei päättelemällä — kolme
  laitetta lukee huoneenlämpöä 0,25 asteen portain.
- **Tai jätä lukematta.** Jos uunianturia katsotaan kolmesti vuodessa, se ei ole
  entiteetin arvoinen.

**Toista isäntää ei tarvita**, eli väylää ei tarvitse jakaa OWFS:n ja ESPHomen
kesken. Tässä luki hetken niin, ja se oli tarpeettoman monimutkainen ratkaisu
ongelmaan joka on ohjelmistopuolella.

Päätös kannattaa silti tehdä vasta kun käynnistysluettelo kertoo mitä väylällä
oikeasti on: jos muita perhekoodeja ei löydy, kysymystä ei ole.

### Osoitemuoto muuntuu laskemalla

OWFS kirjoittaa osoitteen muodossa `28.FF265A750400` — perhekoodi, piste,
sarjanumero. **ESPHome käyttää täyttä 64-bittistä ROM-osoitetta** muodossa
`0x…28`, jossa perhekoodi on alimpana tavuna, sarjanumero käänteisessä
järjestyksessä ja CRC ylimpänä.

**Tässä luki hetken ettei täyttä osoitetta voi laskea, koska CRC ei ole
OWFS-muodossa mukana. Se oli väärin.** CRC ei ole satunnainen tunniste vaan
**laskettu muista seitsemästä tavusta** Dallasin CRC8:lla (polynomi X⁸+X⁵+X⁴+1,
käytännössä reflektoitu 0x8C). Se on siis johdettavissa, ja koko kartta
muuntuu ESPHomen muotoon ilman että väylään kosketaan.

Muunnos on kaksiosainen: **käännä sarjatavut** ja **laske CRC** perhekoodin ja
sarjanumeron yli.

| OWFS | ESPHome |
|---|---|
| `28.FF265A750400` | `0x0E0004755A26FF28` |
| `28.1EF457050000` | `0x8400000557F41E28` |
| `28.799CF6050000` | `0xCB000005F69C7928` |

Kaikki kaksikymmentä on laskettu valmiiksi
[`onewire.yaml`](onewire.yaml):iin nimineen.

**Nimissä huonekoodit on laajennettu, paikkasanat ei.** K on keittiö, KHH
kodinhoitohuone, MH1–MH4 makuuhuoneet ja OH olohuone; "sisä", "ulko", "itä" ja
"ovi katto" jätetään sellaisinaan, koska ne ovat mittauksen kuvauksia eikä niitä
kannata tulkita uudelleen. Alkuperäinen lyhennemuoto säilyy jokaisen anturin
OWFS-kommentissa.

**VH on laajennettu vaatehuoneeksi omistajan muistin mukaan, ei aineistosta.**
Anturit ovat eteläseinän sisä- ja ulkoparina, mikä sopisi yhtä hyvin
vierashuoneeseen — aineisto ei erottele näitä mitenkään. Tämä on ainoa nimi
listassa joka nojaa muistiin eikä tiedostoon, ja lyhenne `VH` säilyy
OWFS-kommentissa siltä varalta että se osoittautuu toiseksi.

**Yksi epävarmuus jää, ja se on tavujärjestys.** Päättely nojaa siihen että
OWFS kirjoittaa sarjatavut vähiten merkitsevä ensin — mikä näkyy siitä että
vanhempien antureiden ylätavut ovat nollia ja ne päätyvät muunnoksessa
`0000`-jaksoksi juuri sinne missä ESPHomen osoitteissa sellainen tyypillisesti
on. Se on vahva viite muttei todiste.

**Ensimmäinen käynnistys ratkaisee sen maksutta:** jos osoite ei vastaa mitään
laitetta, ESPHome sanoo sen suoraan, ja silloin tavujärjestys on väärinpäin.

### Kaksi lähdettä, ja kumpi voittaa missäkin

Aineistoa on kahdenlaista, ja ne eivät ole samanarvoisia:

- **`.txt`-listaukset ovat mitattuja.** Ne ovat OWFS-hakemiston listauksia eli
  sitä mitä väylä raportoi vuonna 2015.
- **PHP-kartta on kirjoitettu.** Se on ihmisen tekemä annotaatio vuodelta 2020.

Ristiriidassa **listaus voittaa olemassaolosta ja PHP nimistä**, koska kumpikin
on ainoa lähde omalle asialleen. Vertailu ei tuottanut ristiriitoja vaan
aikajanan.

**Väylällä oli 22 laitetta, PHP:ssä on 25.** Viisi PHP:n osoitetta puuttuu
listauksista, ja ne ovat kaikki samaa tyyppiä: `MH1 sisä ovi katto`, `KHH sisä
ovi katto`, `K sisä ovi katto`, `OH sisä ovi katto` ja `K sisä`. Verkkoa on siis
laajennettu ovikatto-antureilla vuosien 2015 ja 2020 välillä.

Toiseen suuntaan kaksi laitetta on nimeämättä: **DS18S20 `10.0ED2A0020800`**,
vanhemman polven lämpötila-anturi, ja `81.566632000000` joka on **sovitin
itse** — OWFS näyttää isännän väylän laitteena, joten se ei ole anturi.

### Mitä listaukset kertovat

Tiedostot ovat kumulatiivisia ja nimetty sen mukaan mitä niissä on mukana:
`keuttii.txt`, `keuttiijamakkarit.txt` ja niin edelleen. Asennus eteni huone
kerrallaan — asennettiin, testattiin, otettiin listaus — ja **kunkin askeleen
uudet osoitteet ovat sen huoneen antureita joka nimeen lisättiin.**

| Askel | Uudet anturit | Latch |
|---|---|---|
| keittiö | `28.FF265A750400` K ikkuna sisä · `28.FF897B750400` K ikkuna ulko — **ja isännän pään laitteet**: `26.139121010000` tekninen tila, `10.0ED2A0020800` nimeämätön DS18S20, `81.566632000000` sovitin | `12.892EB6000000` |
| makuuhuoneet | `28.FFEC79760400` MH3 pohjoinen · `28.FF7F35740400` MH3 itä · `28.799CF6050000` MH4 pohjoinen ulko · `28.785317060000` MH4 pohjoinen sisä · `28.65E657050000` MH4 länsi | `12.372EB6000000` |
| olohuone | `28.FFBA7B760400` OH sisä · `28.FF807B750400` OH ulko | `12.BC37B6000000` |
| neljäs | `28.1EF457050000` MH1 etelä sisä · `28.58EF57050000` MH1 länsi · `28.FF5F18730400` MH2 itä · `28.FF4E78760400` VH etelä sisä · `28.FF8276750400` VH etelä ulko | `12.2E30B6000000`, `12.A82DB6000000` |

Ensimmäinen askel sisältää kaksi asiaa sekaisin: keittiön anturit **ja kaiken
mikä on isännän päässä**. Sovitin, teknisen tilan kosteusanturi ja nimeämätön
DS18S20 ilmestyivät heti kun väylä sai virtaa, riippumatta siitä mitä huonetta
oltiin asentamassa. Sen jälkeen jokainen askel tuo nimetyn huoneen anturit ja
yhden kytkintulon.

**Kaksi riippumatonta lähdettä tuottaa saman ryhmittelyn, eikä niissä ole
yhtään ristiriitaa.** Listaukset syntyivät asennettaessa vuonna 2015; nimet
kirjoitettiin PHP:hen erikseen. K-osoitteet ovat keittiön askeleessa, MH3 ja MH4
makuuhuoneiden, OH olohuoneen, MH1 ja MH2 ja VH neljännessä. Se yhtäpitävyys on
vahvempi todiste kuin kumpikaan lähde yksinään.

### Mitä ne eivät kerro

**Onko kukin huone oma sähköinen haaransa, ei ole todistettu.** Jokainen askel
tuo yhden kytkintulon, mikä sopii siihen että jokaisella vedolla on oma
DS2406:nsa keskipisteessä — mutta se on selitys joka sopii havaintoon, ei
havainto itse. Huone ja haara voivat yhtä hyvin olla eri asioita.

Ero merkitsee vain yhdessä tapauksessa: **jos tähti joskus haaroitetaan omille
GPIO-nastoilleen**, silloin tarvitaan tieto vedoista eikä huoneista. Siihen
asti taulukko riittää sellaisenaan, koska se kertoo mitä kukin osoite mittaa.

### Yksi varaus listauksiin

Ne eivät ole identtisissä oloissa otettuja: sovitin ja DS2438 ovat mukana
listauksissa 1, 2 ja 4 mutta puuttuvat listauksesta 3. **Laitteen puuttuminen
yhdestä listauksesta ei siis todista sen poissaoloa.** Ryhmittely on luettu
lisäyksistä eikä puuttumisista, joten tämä ei horjuta taulukkoa.

## Ensimmäinen luettelointi: osoitteet osuivat, mutta väylä ei lue

Väylä on kytketty ja luetteloitu. Tulos ratkaisee kaksi kysymystä ja avaa
yhden uuden.

### Tavujärjestys oli oikein

**19 konfiguraation 20 osoitteesta löytyi väylältä sellaisenaan.** PHP-kartasta
laskettu osoite osui jokaiseen DS18B20:een. Se sulkee yllä jääneen epävarmuuden:
OWFS kirjoittaa sarjatavut vähiten merkitsevä ensin, ja Dallasin CRC8 on
laskettavissa muista tavuista. **Koko osoiteavaruus oli johdettavissa
koskematta väylään**, ja väylä vahvisti sen kerralla.

Ainoa joka ei löytynyt on **DS18S20 `10.0ED2A0020800`**. Se oli isännän pään
laite, ja samasta päästä puuttuu myös **DS2438 `26.139121010000`**. Molemmat
katosivat yhdessä, mikä sopii siihen että ne olivat Raspberryn päässä omassa
tyngässään eivätkä talon tähdessä.

### Väylällä on 38 laitetta, ei 25

| Perhe | Nyt | Kartassa 2020 |
|---|---|---|
| 28 DS18B20 | 28 | 19 |
| 12 DS2406 | 6 | 5 |
| **3B DS1825 / MAX31850** | **3** | 0 |
| 3A DS2413 | 1 | 0 |
| 26 DS2438 | **0** | 1 |

**Ne kolme 3B:tä ovat leivinuunin anturit.** Ne ovat väylällä ja ESPHome
tunnistaa perheen, mutta `dallas_temp` ei lue niitä — kysymys on yhä auki ja
nyt se on konkreettinen eikä hypoteettinen.

### Viisi lukee, viisitoista antaa `nan` — ja ne viisi ovat uusin asennus

Kaikki 20 konfiguroitua julkaisevat joka kierroksella. Viisi antaa lukeman:

```
K sisä · K sisä ovi katto · KHH sisä ovi katto
MH1 sisä ovi katto · OH sisä ovi katto
```

**Ne ovat täsmälleen ne viisi jotka puuttuvat vuoden 2015 listauksista** ja
esiintyvät vain vuoden 2020 PHP-kartassa — yllä oleva ovikattolaajennus. Koko
2015 asennettu tähti on hiljaa; vain sen jälkeen lisätty osa vastaa.

Vastaavuus on täydellinen eikä osittainen, joten kyse ei ole yksittäisistä
vioittuneista antureista vaan **siitä mitä kyseiselle asennusvaiheelle on
yhteistä** — todennäköisimmin oma, lyhyempi vetonsa.

### Luettelointi onnistuu vaikka lukeminen ei, ja se rajaa syyn

ROM-haku löytää kaikki 38. Vasta 750 ms:n muunnos ja 72 bitin
scratchpad-luku epäonnistuvat. Haku on yksinkertaista bittiliikennettä;
lukeminen ei ole. **Vika on siis signaalin laadussa, ei laitteissa eikä
osoitteissa.**

**Yksi muutos kerrallaan.** Jos kaksi asiaa vaihdetaan yhtä aikaa, ei tiedetä
kumpi auttoi — ja seuraavan kerran kun väylä oireilee, tieto puuttuu. Viisi
toimivaa anturia on hyvä mittari: muutos on onnistunut kun luku kasvaa.

> **Tässä kohtaa oli kaksi väärää selitystä peräkkäin.** Ensin ylösvedon
> heikkous, sitten loiskäyttö. Molemmat on kumottu alempana — ensimmäinen
> kokeella, toinen lähdekoodilla — ja ne on jätetty näkyviin vain siltä osin
> kuin niiden kumoaminen tuotti tietoa. **Korjaus ei ole ylösvedossa eikä
> tarkkuudessa.**

### Loki nimeää vian, eikä se ole signaali

`nan` ei kerro mitään yksinään, mutta sitä edeltävä rivi kertoo:

```
[D][dallas.temp.sensor:162]: dropping reading caused by sensor reset
[D][dallas.temp.sensor:054]: 'Makuuhuone 3 itä': Got Temperature=nan°C
```

`dallas_temp` pudottaa lukeman vain yhdellä ehdolla: **lämpötilarekisterissä on
tasan 85,0 °C ja scratchpadin tavu 6 on 0x0C** — DS18B20:n tehdasarvo, se mitä
rekisterissä on ennen ensimmäistä muunnosta.

Kolme asiaa seuraa yhtä aikaa. **Anturi vastaa** — scratchpad luettiin
kokonaan. **CRC on kunnossa** — väärä tarkiste antaisi `checksum invalid`
-varoituksen, ja niitä on kolme koko lokissa eikä neljäätoista kierroksessa.
**Muunnos ei koskaan tapahtunut.**

Kaapeli, liitokset ja käskyjen perillemeno ovat siis kunnossa. Vika on siinä
mitä anturi tekee sen jälkeen kun käsky on vastaanotettu.

### Jako on kategorinen, ja se sulkee pois marginaalin

21 kierrosta, ei yhtään poikkeusta kumpaankaan suuntaan: **viisi onnistui
21/21 ja neljätoista epäonnistui 0/21.** Marginaalivika välkkyisi — 294
yritystä ilman ainuttakaan onnistumista ei ole marginaali vaan kaksi eri
populaatiota.

### Koe joka kumosi oman mallinsa

`resolution: 9` asetettiin neljälletoista ja viisi jätettiin 12 bittiin
verrokiksi. Ajatus oli että loiskäyttöinen anturi käy muunnoksen ajan sisäisen
kondensaattorinsa varassa, jolloin 750 ms → 94 ms olisi kahdeksasosa
vaatimuksesta.

**Tulos oli nolla.** Ei yhtään lukemaa neljästätoista, ei yhtäkään kierrosta,
eivätkä verrokit muuttuneet. Asetus poistettiin: epäonnistunut koe paikalleen
jätettynä luetaan myöhemmin valinnaksi.

### ESPHome ajaa vahvan ylösvedon jo, ja se kaataa loiskäyttöselityksen

Tämä tiedosto väitti kahdessa kohdassa että ESPHomen `gpio`-väylässä ei ole
vahvaa ylösvetoa ja että korjaus vaatisi oman komponentin. **Molemmat olivat
väärin**, ja väite nojasi tiivistelmään lähdekoodista eikä lähdekoodiin.

```cpp
void GPIOOneWireBus::write_bit_(bool bit) {
  this->pin_.digital_write(false);      // veto alas
  delayMicroseconds(delay0);
  this->pin_.digital_write(true);       // OUTPUT-tilassa: ajaa ylös
  delayMicroseconds(delay1);
}
```

Nasta on `FLAG_OUTPUT`-tilassa koko kirjoituksen ajan, joten `digital_write(true)`
**ajaa linjan ylös push-pullina** eikä vapauta sitä vastukselle. `write8()`
päättyy siihen, eikä mikään koske väylään `CONVERT T`:n ja scratchpad-luvun
välissä — **vahva ylösveto on siis päällä koko muunnoksen ajan**, rakenteen
sivutuotteena.

Sama vahvistuu ulkopuolelta: ESPHomen PR [#8077](https://github.com/esphome/esphome/pull/8077)
tarjosi nimenomaan `strong_pullup()`-toimintoa, ja koodin omistaja kommentoi
"the current one wire component already does this". PR suljettiin vanhentuneena.

**Isäntä tarjoaa siis virran jota anturi tarvitsee.** Jos anturit eivät silti
muunna, syy ei ole isännän vetovoimassa — eikä siinä mitä Raspberry teki eri
tavalla, koska se teki saman asian.

### Syy oli väyläkilpailu, ja korjaus on YAML:ia

Oire oli tarkka: ne vastaavat, CRC täsmää, rekisterissä on tehdasarvo. **Ne
puhuvat mutta eivät muunna.** Ratkaisu löytyi `dallas_temp`:n omasta
`update()`-metodista:

```cpp
this->send_command_(DALLAS_COMMAND_START_CONVERSION);
this->set_timeout(..., this->millis_to_wait_for_conversion_(), [this] { ... });
```

**Väylää ei lukita.** CONVERT T lähetetään ja jatketaan `set_timeout`illa, joten
niiden 750 ms:n aikana pääsilmukka pyörii normaalisti — ja jokainen toisen
anturin `update()` aloittaa omalla `reset()`illään, joka vetää linjan alas
480 µs:ksi. Se keskeyttää kesken olevan muunnoksen ja pudottaa vahvan
ylösvedon samalla.

**Linuxin w1-alijärjestelmä pitää väylämutexia koko tapahtuman ajan.** Siinä on
se ero Raspberryyn, jota haettiin koko ilta ylösvedosta, syötöstä ja
kaapeloinnista. Ero oli isännän ohjelmistossa, ei sähkössä eikä talossa.

Se selittää jälkikäteen molemmat aiemmat ristiriidat:

- **21/21 determinismi.** `PollingComponent`-vaiheet lukitaan käynnistyksessä ja
  toistuvat tasan 60 000 ms:n välein, joten samat parit törmäävät identtisesti
  joka kierros.
- **Miksi `resolution: 9` ei auttanut.** Jos törmäys osuu ikkunan alkuun, sen
  lyhentäminen 750 ms:sta 94 ms:iin ei muuta mitään. Kokeen nollatulos ei siis
  kumonnutkaan sitä mitä luulin sen kumoavan.

Korjaus on `update_interval: never` jokaiselle ja yksi `interval`-lohko joka
kutsuu ne läpi sekunnin välein. 23 anturia on 23 s, eli minuuttiin mahtuu.

**Tulos ensimmäisestä ajosta: 46/49 kolmen kierroksen yli.** Jokainen väylällä
oleva anturi lukee. Aiemmin 8/23 luki aina ja 14 ei koskaan.

Jäljelle jäi noin 6 % ajoittaisia ohituksia — `Keittiö ikkuna ulko`,
`Makuuhuone 3 pohjoinen` ja `Makuuhuone 4 pohjoinen ulko` hukkasivat kukin
yhden kierroksen. **Se on sama ajoittaisuus jonka vanha Raspberry-toteutus
näytti**, eli tähden oma signaalinlaatu. Sekunnin väliä voi kasvattaa jos se
alkaa haitata.

### Lukemat vahvistavat nimikartan itsenäisesti

Rakenteen ulkopinnan anturit lukevat kylmempää kuin sisäpinnan, ja ulkona on
14,7 °C stiebelin mittauksen mukaan:

| Pari | sisä | ulko |
|---|---|---|
| Vaatehuone etelä | 21,7 | **16,2** |
| Keittiö ikkuna | 22,7 | **19,5** |
| Makuuhuone 4 pohjoinen | **16,3** | 21,2 |

Kahdella parilla järjestys on oikea, ja se on riippumaton vahvistus koko
PHP-kartasta johdetulle nimeämiselle — ei vain osoitteina vaan sijainteina.

**Makuuhuone 4 pohjoinen on väärinpäin.** 16,3 on ulkoilman lukema, ei
sisäpinnan. Todennäköisin selitys on että sisä ja ulko ovat vaihtuneet vanhassa
kartassa juuri sen parin kohdalla. Nimiä ei silti vaihdeta vielä: yön aikana
ulkoilma laskee ja ero kasvaa, jolloin kumpi on kumpi näkyy kiistatta — ja
nimenvaihto synnyttää uuden entity_id:n, joten se tehdään kerran.

### Ne kolme 3B:tä ovat MAX31850:itä, ja se on mitattu

Kolme kolmesta lukee joka kierroksella, 23,5–24,25 °C. Kaksi asiaa ratkeaa
kerralla.

**Skaalauspäättely piti.** Lukemat ovat huoneenlämpöä eivätkä sen neljäsosa tai
nelinkertainen, joten `raw / 16` on oikein eikä suodatinta tarvita.

**Piiri tunnistuu askeleesta.** Lukemat liikkuvat 0,25 °C:n portain — 23,50 ·
23,75 · 24,00 · 24,25 — kun 12 bitin DS18B20 antaa samassa lokissa 25,0625.
**0,25 °C on MAX31850:n termoparitarkkuus**, DS1825 antaisi 0,0625:n portaita.
Perheen toinen piiri on siis poissuljettu mittaamalla eikä päättelemällä.

Termopari tarkoittaa korkeaa lämpötilaa, ja **omistaja vahvisti että ne ovat
leivinuunissa** — samalla tavalla kuin latchien käyttötarkoitus ja `VH`. Nimet
ovat siksi nyt `Leivinuuni 1`, `2` ja `3`.

**Numero on järjestysluku eikä sijainti.** Mikä niistä on pesässä, mikä
savukanavassa ja mikä massassa, ei ole tiedossa; osoite kunkin vieressä
erottaa ne toisistaan yksikäsitteisesti. Uunin lämmittäminen erottelisi ne
nousunopeudella, ja vasta silloin numeroille voi antaa merkityksen.

Ne saavat myös virtaa, toisin kuin ne neljätoista, eli ne ovat verkon
syötetyssä osassa.

## Ensimmäinen täysi lukema, ja mitä se kertoo

Kun ne yhdeksän tuntematonta lisättiin, **jokainen väylän lämpötilalaite
luki** — 28 DS18B20:tä ja 3 MAX31850:tä. Lukematta jäävät enää kuusi DS2406:tta
ja yksi DS2413.

Tämä on lähtötaso, mitattu 19.9. klo 21:04, ulkoilma 14,7 °C.

### Ulkopinnat erottuvat tiukkana ryhmänä

| | |
|---|---|
| 16,19 | Vaatehuone etelä ulko |
| **16,31** | **Makuuhuone 4 pohjoinen sisä** |
| 16,56 | Olohuone ulko |
| 19,50 | Keittiö ikkuna ulko |

Jokainen muu anturi on 20,9–25,9 °C. Kolme ulkopintaa istuu neljästä viiteen
astetta kaiken muun alapuolella, mikä on **riippumaton vahvistus koko
PHP-kartasta johdetulle nimeämiselle** — ei vain osoitteina vaan sijainteina.

**Ja se paljastaa yhden virheen.** `Makuuhuone 4 pohjoinen sisä` istuu
ulkoryhmässä ja sen pari `ulko` lukee 21,13 eli sisäryhmässä. Kolme paria on
oikein päin, tämä yksi väärin — **sisä ja ulko ovat vaihtuneet vanhassa
kartassa juuri sen parin kohdalla.**

Nimiä ei silti vaihdettu heti: nimenvaihto synnyttää uuden entity_id:n, ja yön
jäähtymiskäyrä tekee asiasta kiistattoman, koska ulkopinnat seuraavat ulkoilmaa
ja sisäpinnat eivät. Se on ilmainen varmistus jota kannatti odottaa.

### Ne yhdeksän tuntematonta ovat kaikki sisällä

```
25,88  BFF565      23,81  FFBADB
25,88  B23B66      23,69  FFC02B
25,38  21270B      23,38  FFF083
24,06  FFAC9D      22,94  FFEAE5
23,75  FF90D8
```

**Yksikään ei ole ulkopinta eikä kuuma piste.** Kaikki ovat välillä 22,9–25,9.

**Saunaa ei siis löytynyt.** Se oli avoin kysymys alusta asti, ja vastaus on
joko ettei sitä ole väylällä tai ettei sitä ollut lämmitetty. Saunan
lämmittäminen ratkaisee sen yhdellä kerralla.

### Eräkoodi kertoo milloin ne on ostettu

Ne eivät ole missään listauksessa eivätkä PHP-kartassa, mutta **osoite itse
kertoo silti jotain.** DS18B20:n sarjanumeron kolme viimeistä tavua ovat
eräkoodi: samasta pussista ostetuilla se on sama. Kun kaikki 28 ryhmitellään
sen mukaan, yhdeksän jakautuu kahtia.

**Viisi on jo talossa olevista eristä — samasta pussista, eri päivänä:**

| Erä | Tuntematon | Samasta erästä tunnettuja |
|---|---|---|
| `050000` | `B23B66`, `BFF565` | MH1 etelä sisä, MH1 länsi, MH4 länsi, MH4 pohjoinen ulko |
| `750400` | `FF90D8`, `FFBADB` | Keittiö ikkuna sisä ja ulko, Olohuone ulko, Vaatehuone etelä ulko |
| `4E0400` | `FFC02B` | Kodinhoitohuone sisä ovi katto, Makuuhuone 1 sisä ovi katto |

**Neljä on eristä joita ei ole missään muualla:**

| Erä | Tuntematon |
|---|---|
| `531502` | `FFAC9D` |
| `031502` | `FFEAE5` |
| `651403` | `FFF083` |
| `070000` | `21270B` |

Kaksi ensimmäistä jakavat päätteen `1502`, eli ne ovat samaa ostoa. Muoto
`1502` ja `1403` poikkeaa kaikesta vanhassa aineistossa, jossa erät ovat
`…0400` ja `…0000`.

**Yhdeksän ei siis ole yksi lisäys vaan vähintään kolme tai neljä.** Viisi on
asennettu vanhoista ylijäämistä ja neljä ostettu myöhemmin.

Yksi erä antaa myös vihjeen sijainnista: **`4E0400` on ovikattoerä**, jonka
molemmat tunnetut jäsenet ovat "sisä ovi katto" -antureita. `FFC02B` on
todennäköisesti kolmas sellainen, huoneessa jota kartta ei kata.

Muut erät eivät auta samalla tavalla. `750400` on enimmäkseen ulkopintoja,
mutta sen tuntemattomat lukevat sisälämpötiloja; `050000` on makuuhuoneita,
mutta sen kaksi tuntematonta ovat koko verkon lämpimimmät. **Eräkoodi kertoo
milloin, ei missä.**

Kaksi havaintoa kannattaa merkitä:

- **`BFF565` ja `B23B66` lukevat täsmälleen saman**, 25,875 °C eli 1/16 asteen
  tarkkuudella identtisen. Ne ovat samassa tilassa tai vierekkäin. Sarjanumerot
  ovat samasta `050000`-erästä kuin vuoden 2015 makuuhuoneanturit.
- **Kolme lämpimintä ovat lämpimämpiä kuin yksikään nimetty huoneanturi**
  kattorajan antureita lukuun ottamatta. Ne ovat siis todennäköisesti
  kattorajassa tai lämmönlähteen lähellä.

### Kolme keinoa tunnistaa loput

| Keino | Mitä erottaa |
|---|---|
| Yön jäähtymiskäyrä | ulkopinnat sisäpinnoista — tapahtuu itsestään |
| Uunin lämmitys 10 min | todistaa ne kolme MAX31850:tä |
| Saunan lämmitys | löytyykö sauna näiden yhdeksän joukosta lainkaan |

Lämpötilaero on tässä paras tunnistusväline, koska se ei vaadi pääsyä
anturille — ja anturit ovat rakenteissa.

## Latchit: kuusi DS2406:tta, joista viisi on kartassa

Perhettä 0x12 on väylällä kuusi. Osoitteet on käännetty takaisin OWFS-muotoon,
ja **viisi kuudesta täsmää vuoden 2015 listauksiin merkilleen**:

| OWFS | ESPHome | 2015-listaus |
|---|---|---|
| `12.372EB6000000` | `0x2B000000B62E3712` | makuuhuoneet |
| `12.2E30B6000000` | `0x38000000B6302E12` | neljäs |
| `12.892EB6000000` | `0x3F000000B62E8912` | keittiö |
| `12.BC37B6000000` | `0xB6000000B637BC12` | olohuone |
| `12.A82DB6000000` | `0xF0000000B62DA812` | neljäs |
| **`12.322EB6000000`** | `0xC0000000B62E3212` | **ei kartassa** |

Tämä on **kolmas riippumaton vahvistus osoitemuunnokselle**: viisi latchia
laskettiin oikein ilman että niitä oli tarkoituskaan lukea.

Kuudennen sarjanumero on `322E` siinä missä makuuhuoneiden on `372E` —
vierekkäisestä erästä, eli lisätty myöhemmin samasta pussista.

### DS2413 on eri piiri, ja ero on juuri se latch

Väylällä on lisäksi yksi **DS2413** (`0x59000000182A3D3A`, perhe 0x3A), jota ei
ole vanhassa kartassa lainkaan.

Sekä DS2406 että DS2413 ovat osoitteellisia kytkimiä: kaksi avokollektorikanavaa
jotka voi vetää alas tai vapauttaa, ja joiden tila voi lukea takaisin. Yhdellä
väylällä ne näyttävät samankaltaisilta. Ero on siinä mikä antoi latcheille
nimensä:

| | DS2406 (0x12) | DS2413 (0x3A) |
|---|---|---|
| Kanavia | 1 tai 2 | 2 |
| **Tapahtumasalpa** | **on** | **ei ole** |
| EPROM | 1 kbit | ei |
| Kotelo | TO-92 / TSOC-6 | TSOC-6 |

**DS2406 muistaa että tila muuttui, vaikka se olisi jo palannut ennalleen.**
Se on se `latch`-ominaisuus jonka OWFS näyttää ja jonka mukaan vanhan
toteutuksen listaukset on nimetty. Isäntä nollaa salvan lukiessaan, ja seuraava
lukukerta kertoo taas tapahtuiko välissä mitään.

**DS2413:ssa sitä ei ole.** Se kertoo vain tilan sillä hetkellä kun sitä
kysytään. Jos nämä ovat ovi- tai ikkunakoskettimia ja niitä pollataan kymmenen
sekunnin välein, **DS2406 huomaa nopean avaus-sulkemisen ja DS2413 ei.**

Se tekee DS2413:sta huonomman valinnan tähän käyttöön — ja sitä kautta se on
vihje siitä, että se **ei ole samaa tarkoitusta varten** kuin ne kuusi. Se on
myös myöhempi lisäys, kuten kuudes DS2406 ja ne yhdeksän tuntematonta
lämpötila-anturia.

### Valmis komponentti on olemassa, mutta se ei ole ESPHomessa

[PR #8091](https://github.com/esphome/esphome/pull/8091), `dallas_pio` —
tukee DS2413:a, DS2406:tta ja DS2408:aa ja tarjoaa niille sekä
`binary_sensor`- että `switch`-alustan. **PR suljettiin vanhentuneena**
lokakuussa 2025, ei siksi ettei se toimisi: huomautukset koskivat
arkkitehtuuria ja tiheän pollauksen suorituskykyä. Latchin lukeminen
kymmenen sekunnin välein ei ole se käyttötapaus.

Haara on yhä olemassa ja komponentti täydellinen:

```
tdy91/esphome @ feature_dallas_pio
3e8806f7aace402a19c85ff38918ff702da53132   19.4.2025
```

```yaml
external_components:
  - source:
      type: git
      url: https://github.com/tdy91/esphome
      ref: 3e8806f7aace402a19c85ff38918ff702da53132   # täysi sha, ei lyhennettä

    components: [dallas_pio]

dallas_pio:
  - id: latch_keittio
    reference: DS2406
    address: 0x3F000000B62E8912
    one_wire_id: bus_a

binary_sensor:
  - platform: dallas_pio
    name: "Latch keittiö"
    dallas_pio_id: latch_keittio
    pin:
      number: PIOA
      mode:
        input: true
    update_interval: 10s
```

**`ref:` on tässä tärkeämpi kuin missään muualla repossa.** Se on
yksityishenkilön haara suljetussa PR:ssä — se voi kadota tai rebasoitua milloin
tahansa, eikä kukaan ylläpidä sitä. Tämä on sama `@main`-ongelma jonka repo on
kirjannut jo kolmesti, nyt pahimmassa mahdollisessa muodossaan.

**Ja sha on annettava kokonaisena.** Lyhennetty muoto kaatuu:

```
couldn't find remote ref 3e8806f7aace
```

ESPHome ei resolvoi lyhennettä vaan antaa sen gitille sellaisenaan, eikä
`git`-protokolla tunne osittaisia viitteitä — palvelin joko tunnistaa täyden
objektinimen tai ei mitään. Aidonin `ref` on samasta syystä 40 merkkiä.
**Lyhennetty sha näyttää dokumentissa siistimmältä ja rikkoo käännöksen**, eli
se on juuri sellainen kauneusvirhe joka kannattaa kirjata.

### Se ei käänny 2026.9.0:lla, ja tässä on mitä portti vaatii

Versioero toteutui. Komponentti on kirjoitettu ESPHome 2025.4:ää vasten ja
`one_wire`-rajapinta on muuttunut kolmesta kohdasta. Konfiguraatio palautettiin
kääntyvään tilaan; tämä luku on se mitä portti vaatii, jotta se ei ole
uudelleen selvitettävä.

**1. `check_address_()` → `check_address_or_index_()`**

```
error: 'DallasPio' has no member named 'check_address_'
```

`OneWireDevice` tarjoaa nyt `check_address_or_index_()`. Komponentissa on myös
oma `DallasPio::check_address()`-kääre joka kutsuu vanhaa nimeä — **pelkkä
alaviivan poisto tekisi siitä ikuisen rekursion**, joten kääre poistetaan ja
kutsut ohjataan suoraan perittyyn metodiin.

**2. `bus_->reset()` → ei ole olemassa julkisena**

```
error: 'OneWireBus' has no member named 'reset'; did you mean 'reset_'?
```

`reset_()` on nykyään **protected**, eikä ulkopuolinen komponentti voi kutsua
sitä. Se ei silti ole este: julkisia ovat `select(address)`, `write8`, `read8`,
`write64`, `read64`, `skip()` ja `search()`, ja `OneWireDevice` tarjoaa
`send_command_(cmd)` joka tekee resetin, MATCH ROMin ja käskyn kerralla.
**Vanha `reset()` + käsin tehty osoitteenvalinta korvautuu yhdellä
`send_command_`-kutsulla.**

**3. `using EntityBase::set_name;` ei käänny**

```
error: 'set_name' has not been declared in 'class EntityBase'
```

`switch.h`:ssa. Koskee vain switch-alustaa — **ovisensorit tarvitsevat vain
`binary_sensor`in**, joten switch-tiedostot voi jättää portista kokonaan pois.

### Miten portti kannattaa tehdä

**Ei paikallisena kopiona.** `vendor/` on gitignoressa, joten patch jäisi
versionhallinnan ulkopuolelle ja katoaisi ensimmäisen koneen vaihdon mukana.

**Haarukoi `tdy91/esphome`, korjaa nuo kolme ja osoita `ref:` omaan
committiin.** Silloin konfiguraatio on toistettava ja repo pysyy puhtaana
kolmannen osapuolen koodista, kuten sen säännön mukaan pitää.

Vaihtoehto on **kirjoittaa vain se mitä tarvitaan**: DS2406:n tilan luku on
`send_command_(0xF5)`, kaksi ohjaustavua ja yksi luettu tavu. Se on murto-osa
`dallas_pio`:sta, joka kattaa kolme piiriä sekä luvun että kirjoituksen — ja
tästä tarvitaan vain yhden piirin luku.

### Mutta ennen koodia: mitä ne mittaavat

**Yksi latch per asennusvaihe on outo kuvio.** Ovikoskettimet seuraisivat ovia,
eivät asennuspäiviä. Todennäköisempää on että DS2406:t ovat haarakohtaisia,
jolloin ne kertoisivat jotain tähden rakenteesta eivätkä talon tapahtumista.

Komponentin kääntäminen ei vastaa tähän. **Selvitä ensin mihin ne on kytketty**,
ja vasta sitten päätä kannattaako niitä lukea — muuten syntyy kuusi entiteettiä
joiden arvoa kukaan ei osaa tulkita.

## Kytkös lattialämmitykseen

Jos anturit ovat lattiavalussa, tämä projekti menee päällekkäin
[stiebel.eltronin](../stiebel.eltron/CLAUDE.md) jakotukkisuunnitelman kanssa —
ja on sitä parempi.

Se suunnitelma asentaa DS18B20:n jokaisen piirin paluuputkeen ja lukee lattian
lämpötilaa epäsuorasti kiertopumpun seisokin aikana. Kiertotie on olemassa
koska suoraa mittausta ei ole. **Valuun asennettu anturi on suora mittaus**, ja
se tekisi 25 anturin asennuksesta joko tarpeettoman tai paljon pienemmän.

Tätä ei pidä olettaa ennen kuin sijainnit on kartoitettu. Mutta jos se osoittuu
todeksi, se on tämän projektin arvokkain anti eikä se lämpötilalukema.

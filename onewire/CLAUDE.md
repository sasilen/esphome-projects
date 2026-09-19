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

- **Verkko on 3,3 voltin verkko.** Raspberryn 1-Wire on 3,3 V, joten syöttö ja
  ylösveto ovat sillä tasolla. C3:n 3V3 on suoraan oikea, eikä datalinjassa voi
  olla 5 V:a joka tappaisi GPIO:n — riski joka 5 voltin 1-Wire-verkossa olisi
  todellinen.
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

### ESPHome ei lue kaikkea tätä

`dallas_temp` kattaa DS18B20:n ja DS18S20:n, eli **ne 19 lämpötila-anturia**.
**DS2438 ja DS2406 eivät ole ESPHomen omissa komponenteissa**, joten kosteus ja
viisi kytkintuloa jäisivät lukematta. Tämä on tarkistettava asennetusta
versiosta ennen kuin siihen nojaa, mutta suunta on selvä: jos ne halutaan
mukaan, tarvitaan OWFS rinnalle tai tilalle.

Se on todellinen valinta eikä tekninen este: 19 anturia 25:stä on valtaosa, ja
kosteus teknisessä tilassa on yksi lukema.

### Osoitemuoto ei ole sama

OWFS kirjoittaa osoitteen muodossa `28.FF265A750400` — perhekoodi, piste,
sarjanumero. **ESPHome käyttää täyttä 64-bittistä ROM-osoitetta** muodossa
`0x…28`, jossa perhekoodi on alimpana tavuna, sarjanumero käänteisessä
järjestyksessä ja CRC ylimpänä.

`28.FF265A750400` vastaa siis ESPHomessa osoitetta joka päättyy `FF28`:aan ja
jonka keskeltä löytyy `04755A26` käänteisenä. **CRC ei ole OWFS-muodossa
mukana**, joten täyttä osoitetta ei voi laskea — mutta sitä ei tarvitsekaan:
ESPHome luetteloi löytämänsä osoitteet itse, ja nimi liitetään niihin
täsmäämällä sarjanumeron numerot. Kartoitusajo tuottaa siis osoitteet ja tämä
taulukko nimet.

### Mitä vanhoista listauksista jäi

Vuoden 2015 listaukset oli otettu haara kerrallaan ja tallennettu kumulatiivisina
tiedostoina, mikä antaa haarakohtaisen ryhmittelyn: keittiö kuusi laitetta,
makuuhuoneet kuusi lisää, olohuone kolme, neljäs haara seitsemän.

Ne sisältävät myös kaksi laitetta joita PHP:n kartassa ei ole: **DS18S20
`10.0ED2A0020800`** eli nimeämätön vanhemman polven lämpötila-anturi, ja
`81.566632000000` joka on **DS2490 eli sovitin itse** — OWFS näyttää isännän
väylän laitteena.

Ja toisin päin: PHP:n kartassa on viisi osoitetta joita vuoden 2015 listauksissa
ei ole. Verkko on siis kasvanut välissä, ja **PHP on niistä uudempi ja
täydellisempi lähde.**

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

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

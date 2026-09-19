# Talon 1-Wire-väylä → Home Assistant

> **Yleiskuva.** Tekniset tiedot ja perustelut: [CLAUDE.md](CLAUDE.md).

Talossa on **valmis 1-Wire-verkko jossa on DS18B20-antureita**, eikä se ole
käytössä. Kaapelointi ja anturit ovat siis molemmat jo paikoillaan; puuttuu vain
isäntä ja konfiguraatio.

Tämä on repon ensimmäinen projekti joka alkaa olemassa olevasta
infrastruktuurista. Kaikki muut ovat alkaneet tyhjästä laatikosta.

## Tila

**Kartoitus kesken.** Kolme asiaa on selvittämättä, ja ne ratkaisevat mitä tästä
tulee:

| Kysymys | Miksi se ratkaisee |
|---|---|
| Montako anturia väylällä on? | määrää levyvalinnan ja entiteettimäärän |
| Missä ne fyysisesti ovat? | määrää onko tämä mittausprojekti vai uteliaisuus |
| Miksi verkko ei ole käytössä? | jos se hylättiin epäluotettavana, syy on todennäköisesti topologia |

Erityisesti kolmas: jos anturit ovat **lattiavalussa**, tämä muuttaa
[stiebel.eltronin](../stiebel.eltron/) jakotukkisuunnitelman. Se 25 anturin
asennus on olemassa nimenomaan siksi ettei lattian lämpötilaa pääse mittaamaan
suoraan, ja jakotukin paluuanturit kiertopumpun seisokin aikana ovat kiertotie
sen ympäri. Suora lattia-anturi on parempi mittaus, ja se olisi jo seinässä.

## Kytkentä

![Kartoituskytkentä](wiring.svg)

Kolme johdinta ja yksi vastus. **Ylösveto kuuluu isännän päähän**, datan ja
3,3 voltin väliin, ja niitä on yksi kappale koko verkolle — ei yhtä per haara,
koska rinnakkaiset ylösvedot laskisivat yhteisvastuksen liian pieneksi.

| C3 | | Keskipiste |
|---|---|---|
| 3V3 | → | VDD |
| GPIO4 | → | DQ, ja **4,7 kΩ tästä 3,3 V:iin** |
| GND | → | GND |

GPIO4 samasta syystä kuin stiebelin solmussa: SuperMinillä se on samalla
reunalla kuin 3V3 ja GND, eikä se ole strappausnasta.

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

**Maa ensin, ja se on tärkeysjärjestys eikä tapa.** DQ:n ja VDD:n sekoittaminen
on toivuttavaa; maan ja VDD:n sekoittaminen ei ole.

## Kartoitusajo

1. Flashaa [`discovery.yaml`](discovery.yaml) — siinä ei ole yhtään sensoria
2. Lue käynnistyksen tuloste
3. **Käynnistä uudelleen pari kertaa ja vertaa luetteloa**

Kolmas askel on se joka erottaa toimivan verkon marginaalisesta. Yksi onnistunut
luettelo ei todista mitään: tähtitopologian vika on nimenomaan se että osa
antureista löytyy ja osa ei, ja löytyneet vaihtuvat ajojen välillä. **Sama
luettelo kolmesti tarkoittaa että topologia ei ole tässä verkossa ongelma.**

**Älä laske lokitasoa INFO:on.** Osoiteluettelo tulostuu CONFIG-tason
vedoksessa, ja INFO vaientaa juuri sen rivin jota ollaan hakemassa — tuloste
näyttää silloin siltä ettei antureita löytynyt lainkaan. Sama mekanismi piilotti
solmun IP-osoitteen stiebelin käyttöönotossa ja maksoi siellä yhden kierroksen.

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

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

## Ensimmäinen koe

Kymmenen minuuttia, ei osaostoja, ei juotosta.

1. Levy kiinni väylän keskipisteeseen: **data GPIO:hon, 4,7 kΩ ylösveto 3,3 V:iin**
2. Flashaa [`discovery.yaml`](discovery.yaml) — siinä ei ole yhtään sensoria
3. Lue käynnistyksen tuloste

ESPHome luetteloi löytämänsä ROM-osoitteet. Yksi käynnistys kertoo montako
anturia väylällä on ja mitkä ne ovat.

**Älä laske lokitasoa INFO:on.** Osoiteluettelo tulostuu CONFIG-tason
vedoksessa, ja INFO vaientaa sen. Sama mekanismi piilotti solmun IP-osoitteen
stiebelin käyttöönotossa ja maksoi siellä yhden turhan kierroksen.

## Mitä sen jälkeen

Osoite on pysyvä ja yksilöllinen mutta se ei kerro sijainnista mitään.
Kartoitus tehdään menetelmällä joka on tässä repossa todettu vahvimmaksi:
**muuta yhtä asiaa ja katso väylää.** Lämmitä yksi anturi kädellä ja katso mikä
osoite liikkuu. Kymmenen sekuntia per anturi, eikä jälkikäteen jää mitään
tulkittavaa.

Jos anturit ovat seinän sisässä eikä niihin pääse käsiksi, kartoitus tapahtuu
lämmityksen kautta ja on hitaampi — mutta se on silti sama menetelmä.

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

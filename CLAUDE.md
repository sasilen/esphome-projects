# CLAUDE.md — esphome-projects

> **Repon konventiot.** Yleiskuva ja projektilista: [README.md](README.md).

Kotiautomaatioprojekteja ESPHomella. Repo sisältää **vain dokumentaatiota ja
konfiguraatiota** — ei kolmannen osapuolen koodia.

## Kieli

Käyttäjä kommunikoi suomeksi. Vastaa suomeksi, myös koodikommenteissa.

Dokumenttien kieli on projektikohtainen eikä sitä yhtenäistetä: aidon, hirvirata,
axioma.effection ja bestway.lay-z-spa suomeksi, stiebel.eltron ja
pegasos.enervent englanniksi. **Kirjoita aina sen tiedoston kielellä jota
muokkaat.** Projektin README ja CLAUDE.md ovat samalla kielellä.

Tiedostonimet ovat englanniksi vaikka sisältö on suomea.

## Kolme dokumenttia

| Tiedosto | Nimitys | Kysymys | Aikamuoto |
|---|---|---|---|
| `README.md` | Yleiskuva | Mikä tämä on, ja kannattaako tehdä? | preesens, käskymuoto |
| `CLAUDE.md` | Tekniset tiedot ja perustelut | Miten rakennettu ja miksi näin? | preesens, toteava |
| `BUILDLOG.md` | Rakennuskertomus | Miten tähän päädyttiin? | imperfekti, minämuoto |

Aikamuoto on käyttökelpoinen testi: jos lause on imperfektissä, se kuuluu
buildlogiin. Jos se kertoo mitä *nyt* on, se kuuluu README:hen tai CLAUDE.md:hen.

Käytä näitä nimityksiä kaikkialla samoina. Jokainen dokumentti alkaa
navigointirivillä joka osoittaa muihin.

**Älä toista samaa asiaa README:ssä ja CLAUDE.md:ssä.** README kertoo mitä
tehdään, CLAUDE.md miksi juuri niin. Jos perustelu on molemmissa, se kuuluu vain
CLAUDE.md:hen.

## Buildlog

Kun projekti valmistuu, sille kirjoitetaan `BUILDLOG.md`: mitä tilattiin, mitä
juotettiin, mikä meni pieleen ja mitä tekisi toisin. Umpikujat ja väärät
oletukset ovat sen arvokkainta antia.

Buildlog **päivätään ja jäädytetään.** Vanhentuvaa kohtaa ei korjata jälkikäteen
— se oli totta kirjoitushetkellä. Ajantasainen tieto on README:ssä ja
CLAUDE.md:ssä. `aidon/BUILDLOG.md` on jäädytetty elokuun 2026 tilanteeseen; älä
muokkaa sen sisältöä.

Rakentamattomalle projektille ei kirjoiteta buildlogia.

## Hakemistot ja nimeäminen

Projektihakemisto on `valmistaja.malli` pienellä (`stiebel.eltron`,
`pegasos.enervent`, `bestway.lay-z-spa`) tai laitteen vakiintunut nimi
(`aidon`, `hirvirata`).

## Salaisuudet

`secrets.yaml` ei mene koskaan versionhallintaan — `.gitignore` estää sen.
Jokaisessa projektissa on `secrets.yaml.example`. YAMLissa käytetään aina
`!secret`-viittauksia, ei kirjoitettuja arvoja.

## Ulkopuolinen koodi

Kolmannen osapuolen firmwarea ei kopioida repoon, vaan siihen linkitetään
lähteessään. `upstream/`- ja `vendor/`-hakemistot ovat gitignoressa, joten
työkopion voi ladata projektihakemistoon paikallisesti.

`bestway.lay-z-spa` on tästä esimerkki: firmware on visualapproachin GPL-3-työtä
eikä sitä säilytetä täällä.

## Git

**Repo on julkinen.** Ennen committia tarkista ettei tekstiin jää tunnistetietoa
— sarjanumeroita, tarkkoja osoitteita, tilinumeroita. Vesimittarin sarjanumero on
korvattu paikanpitäjällä `12345678` tästä syystä.

Sama koskee **valokuvia, joissa tunnistetieto on metadatassa eikä kuvassa**.
Puhelimen ottama kuva sisältää GPS-koordinaatit muutaman metrin tarkkuudella.
Aja jokainen kuva tämän läpi ennen committia:

```sh
convert kuva.jpg -auto-orient -strip -resize 1600x -quality 82 projekti/nimi.jpg
```

`-strip` poistaa metadatan, `-auto-orient` pitää kuvan oikein päin sitä ennen.
Tarkista jälkikäteen: `identify -verbose nimi.jpg | grep -i gps` ei saa tulostaa
mitään.

Tekijätieto on `Sami <4187961+sasilen@users.noreply.github.com>`. Älä ehdota
työsähköpostia äläkä koneen generoimaa osoitetta.

Commit-viestit suomeksi, imperatiivissa ("Korjaa", "Lisää", "Yhtenäistä").

## ESPHome-ympäristö

Home Assistant pyörii Podman-kontissa, joten ESPHome-lisäosaa ei ole. ESPHome on
oma konttinsa, `Network=host` pakollinen — muuten mDNS ei toimi eikä OTA löydä
levyjä. Tavoite kaikissa projekteissa on paikallinen ohjaus ilman pilveä ja
ESPHome-projekteissa ilman MQTT:tä.

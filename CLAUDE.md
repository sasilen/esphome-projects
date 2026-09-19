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
Jokaisella ESPHome-konfiguraation omaavalla projektilla on `secrets.yaml.example`
(aidon, hirvirata, stiebel.eltron). Suunnitteluvaiheen projektit saavat omansa
samalla kun YAML syntyy; `bestway.lay-z-spa` ei ole ESPHome-projekti eikä
kuulu tämän piiriin.

YAMLissa käytetään aina `!secret`-viittauksia, ei kirjoitettuja arvoja.
**Tämä koskee myös AP-varayhteyden salasanaa** — se unohtuu helposti, koska se
tuntuu laitteen omalta asetukselta eikä verkon tunnukselta. AP:n *nimi* sen
sijaan ei ole salaisuus: se lähetetään ilmaan.

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

### Kontin `/config` ei ole tämä repo

Siellä on **pelkkiä YAMLeja**, vietynä sinne erikseen. Repo ei ole mountattuna,
eikä mikään muu kuin konfiguraatiotiedosto ole siellä ennen kuin se kopioidaan.

Se ei näy mitenkään ennen kuin jokin muu kuin YAML tarvitaan. Oma komponentti
`external_components: type: local` -lohkossa kaatoi käännöksen kahdesti, koska
polku ratkeaa kontin `/config`:sta eikä repon puolelta:

```
Could not find directory '/config/components'
```

**Vie hakemisto erikseen, ja polku on sen jälkeen `/config`:n suhteen:**

```sh
podman cp onewire/components esphome:/config/components
```

Kaksi asiaa seuraa tästä:

- **Koodi on kahdessa paikassa ja ne voivat erkaantua.** Repo on se joka on
  oikeassa; kontin kopio on käännösartefakti. Jos käännös käyttäytyy oudosti
  muutoksen jälkeen, **kopioi uudestaan ennen kuin epäilet koodia** — se on
  sama oire kuin vanhentunut käännöshakemisto alempana.
- **Sama koskee kaikkea muutakin kuin YAMLia**: `secrets.yaml`, mahdolliset
  paketit ja jaetut lohkot. Jos tiedostoon viitataan konfiguraatiosta, sen on
  oltava `/config`:n alla.

## Kontti päivittyy itsestään, ja se rikkoo käännöshakemiston

Quadletissa on `AutoUpdate=registry`, eli image vaihtuu taustalla. Kerran se
näkyi näin:

```
'/root/.cache/esphome/idf/penvs/5.5.5/bin/python' is currently active in the
environment while the project was configured with
'/config/.esphome/idf/penvs/5.5.5/bin/python'.
```

ESP-IDF:n välimuisti oli siirtynyt imagen mukana, ja **käännös kaatui — mutta
`esphome run` ei näyttänyt siltä kuin mitään olisi vialla.** Laite vain ei
käynnistynyt uudelleen. Vika löytyi vasta lokista: `Uptime` juoksi
katkeamattomana yhdeksän tuntia, eli OTA:ta ei koskaan yritetty.

**Korjaus on `esphome clean` ja uusi käännös.**

Kaksi asiaa kannattaa ottaa tästä:

- **Todenna OTA laitteesta, älä komennon paluuarvosta.** `Uptime`-anturi kertoo
  menikö se perille; komento voi onnistua näennäisesti.
- Tämä on sama ilmiö kuin liikkuva versioviittaus, yhtä kerrosta alempana.
  Repossa on kirjattu kolmesti mitä `@main` tekee; `AutoUpdate=registry` on
  sama asia käännösympäristölle. **Sama YAML voi kääntyä eri tavalla ilman että
  repossa muuttuu mitään.**

## Boottirivi ei kelpaa todisteeksi — se toistuu jokaiselle lokiasiakkaalle

Tässä luki että `Uptime`-anturi **tai boottirivi** kertoo menikö OTA perille.
Boottirivi ei kerro: **ESPHome toistaa koko kokoonpanotulosteen aina kun uusi
lokiasiakas liittyy**, alkaen rivistä `ESPHome version … compiled on …`.

Axioman lokissa on kolme sellaista banneria kymmenen sekunnin sisällä, mikä
lukee boot-loopilta. Laite ei käynnistynyt kertaakaan: `Uptime` juoksi samaan
aikaan katkeamattomana 4624 sekunnista 4864:ään. Bannerien määrä kertoi
asiakkaista.

**`Uptime` on ainoa rivi joka erottaa uudelleenkäynnistyksen liittymisestä**, ja
`sensor`-tagin vaientaminen `logger:`-lohkossa hävittää juuri sen.

Sivutuote joka on hyödyllinen: kokoonpanotulosteen saa uudelleen milloin
tahansa liittämällä lokiasiakkaan — mutta **setup-vaihetta se ei toista.**
Radion alustusrivit ja mahdollinen paniikin backtrace tapahtuvat ennen kuin API
on pystyssä, ja ne näkee vain sarjaportista.

## OTA kaatuu jos laitteella on liikaa asiakkaita

Toinen OTA-yritys eteni 33 %:iin ja katkesi aikakatkaisuun, ja laite katosi
verkosta kokonaan. Laitteella oli samaan aikaan kolme asiakasta: Home Assistant,
`esphome logs` -virta ja OTA itse. Flash-kirjoituksen aikana se on liikaa.

**Pysäytä lokivirta lähetyksen ajaksi**, niin se menee läpi:

```sh
pkill -f "esphome logs"
# Install → Wirelessly, tai esphome run --no-logs
podman exec esphome esphome logs /config/laite.yaml >> laite.log 2>&1 &
```

Käytä `>>` eikä `>`. Uudelleenohjaus nollasi axioman lokin kolmesti, ja kerran
se vei mennessään yön mittausaineiston — analyysi oli onneksi jo commitissa.
Tee siitä skripti jos sama loki käynnistetään usein.

Rinnalla kannattaa asettaa **`power_save_mode: NONE`**. Oletus `LIGHT` nukuttaa
radion majakkavälien välissä, ja megatavun OTA on tuhansia kuittauskierroksia
joista jokaiseen tulee herätysviive. Aidonin avointen asioiden lista suosittelee
samaa ensimmäisenä keinona heikkoon radioon.

Jos OTA katkeaa vielä näidenkin jälkeen, seuraava epäilty on virtalähde:
flash-kirjoitus ja WiFi-lähetys yhtä aikaa on se hetki jolloin heikko syöttö
notkahtaa.

**Keskeytynyt OTA ei riko mitään** — ESP32:n rollback palauttaa toimivan
imagen, ja niin se teki tässäkin.

#!/bin/sh
# Ilmoittaa CAN-väylän kirjoituksista jotka eivät ole tunnettua rutiinia.
#
# Käyttö:  ./watch-writes.sh <loki> [tunnit]
#
# **Miksi tämä on olemassa.** Asetusparametrit asuvat EEPROMissa, jolla on
# rajallinen kirjoitusmäärä, ja tällä väylällä on nyt ensimmäistä kertaa solmu
# joka osaa kirjoittaa. Oma vahti kymmenen minuutin välein rajaa meidän
# kirjoituksemme, mutta se ei näe mitä muut tekevät — eikä se näe omaa vikaansa
# jos jokin ohittaa sen.
#
# **Erotin on harvinaisuus, ei osoite.** Manageri kirjoittaa 0x700:lle
# sekunneittain: 20.9. mennessä yli 13 000 kertaa neljälle elementille.
# Mikään EEPROM ei kestäisi sitä, joten ne ovat säätölähtöjä eivätkä
# tallennettavia arvoja. Harvinainen kirjoitus on se joka kannattaa nähdä —
# legionellakytkin näkyi lokissa täsmälleen kerran.
#
# Suodatettu pois tunnettuna rutiinina:
#
#   480>700  FE1B FE1C FE1D FE1E   säätölähtöjä, sekunneittain
#   100>480  06AF                  7 min välein, arvo vakio 1
#   480>100  080E                  managerin oma
#   480>100  0122-0126             kello: päivä, kk, vuosi, tunti, minuutti
#   601>301  0052                  sekoitusmoduulin oma
#   480>100  1388                  tilakoodi, 7 min välein
#
# Kaikki muu tulostetaan. **Myös oma solmu 0x680** — jos se alkaa kirjoittaa
# toistuvasti, se näkyy täällä ennen kuin EEPROM huomaa.
#
# **Tämä vahti vaatii `Log every frame` -kytkimen päälle, ja se on pois joka
# boottauksen jälkeen** (`restore_mode: ALWAYS_OFF`). Kytkin pois päältä
# käsittelijä lokittaa vain kehykset joita se ei osannut purkaa — eli juuri
# tunnetut asetusrekisterit katoavat. Paneelista tehty muutos kuten
# `100>180 wr ex=0013` on purettava kehys, joten se jäisi näkymättä, ja se on
# tämän vahdin tärkein käyttötapaus. Legionellakytkin näkyi 20.9. vain koska
# kytkin sattui olemaan päällä.
#
# Vahti tarkistaa sen käynnistyessä ja kieltäytyy lähtemästä ilman. Jos haluat
# silti nähdä purkamattomat kirjoitukset, anna kolmanneksi argumentiksi
# `osittain` — silloin se sanoo ääneen mitä se ei näe.
#
# **Hinta on lokin koko.** Kytkin päällä jokainen kehys kirjataan, eli noin
# 220 riviä minuutissa 19:n sijaan. Vuorokausi on satojatuhansia rivejä.

# **Vahti tarkkailee myös lokia itseään.** Jos lokivirta kuolee, vahti
# raportoi hiljaisuutta joka näyttää samalta kuin rauhallinen väylä. Niin
# kävi 21.9.: fläshäyksen `pkill -f "esphome logs"` tappoi molemmat virrat
# ja vain toinen käynnistettiin uudelleen. Tämä poistuu virheellä jos
# tiedosto ei kasva viiteen minuuttiin.

# **`grep -c` tulostaa nollan ja palauttaa silti epätoden.** `|| echo 0`
# lisää siihen toisen nollan, jolloin `[ "0\n0" -eq 0 ]` kaatuu eikä
# ehtolause toteudu — ja tarkistus, jonka piti pysäyttää vahti, päästää sen
# läpi. Vika osuu siis aina auki-suuntaan. Käytä `|| true`.

set -eu

LOG="${1:?anna lokitiedosto}"
TUNNIT="${2:-24}"
MITEN="${3:-taysi}"
LOPPU=$(( $(date +%s) + TUNNIT * 3600 ))

# **Onko `Log every frame` päällä?** Puretut kehykset päätyvät lokiin vain
# silloin, ja oma pollivastauksemme on niistä helpoin tunnistaa. Katso vain
# tuoreesta hännästä: vanhassa aineistossa niitä on, vaikka kytkin olisi nyt
# pois.
if [ "$(tail -600 "$LOG" | grep -ac ">680 resp" || true)" -eq 0 ]; then
    if [ "$MITEN" = "osittain" ]; then
        echo "[kirjoitusvahti] VAROITUS: Log every frame näyttää olevan pois."
        echo "[kirjoitusvahti] En näe purettuja kirjoituksia — esim. paneelin"
        echo "[kirjoitusvahti] asetusmuutoksia. Vain tuntemattomat rekisterit."
    else
        echo "[kirjoitusvahti] Log every frame on pois, enkä näkisi paneelin"
        echo "[kirjoitusvahti] tekemiä asetusmuutoksia lainkaan. Kytke se HA:sta"
        echo "[kirjoitusvahti] päälle, tai aja 'osittain'-argumentilla."
        exit 1
    fi
fi

# Aloita lokin nykyisestä lopusta, ei alusta
RIVI=$(wc -l < "$LOG")

echo "[kirjoitusvahti] $LOG, rivistä $RIVI, kesto ${TUNNIT} h"

rutiini() {
    # Palauttaa 0 jos rivi on tunnettua rutiinia
    case "$1" in
        *"480>700 wr   ex=FE1B"*|*"480>700 wr   ex=FE1C"*) return 0;;
        *"480>700 wr   ex=FE1D"*|*"480>700 wr   ex=FE1E"*) return 0;;
        *"100>480 wr   ex=06AF"*|*"480>100 wr   ex=080E"*) return 0;;
        *"480>100 wr   ex=012"*|*"601>301 wr    e=0052"*)  return 0;;
        *"480>100 wr   ex=1388"*) return 0;;
    esac
    return 1
}

KOKO=$(wc -c < "$LOG")
KUOLLUT=0

while [ "$(date +%s)" -lt "$LOPPU" ]; do
    UUSI_KOKO=$(wc -c < "$LOG")
    if [ "$UUSI_KOKO" -eq "$KOKO" ]; then
        KUOLLUT=$(( KUOLLUT + 1 ))
        if [ "$KUOLLUT" -ge 10 ]; then
            echo "[vahti] LOKI EI KASVA viiteen minuuttiin — en näe mitään"
            ls -l "$LOG"
            exit 2
        fi
    else
        KUOLLUT=0
        KOKO=$UUSI_KOKO
    fi

    UUDET=$(tail -n "+$((RIVI + 1))" "$LOG" 2>/dev/null | grep -a " wr " || true)
    KAIKKI=$(wc -l < "$LOG")
    if [ "$KAIKKI" -gt "$RIVI" ]; then
        RIVI=$KAIKKI
        printf '%s\n' "$UUDET" | while IFS= read -r r; do
            [ -n "$r" ] || continue
            if ! rutiini "$r"; then
                echo "[kirjoitusvahti] EI RUTIINIA:"
                printf '  %s\n' "$r"
            fi
        done
    fi
    sleep 30
done

echo "[kirjoitusvahti] aika loppui"

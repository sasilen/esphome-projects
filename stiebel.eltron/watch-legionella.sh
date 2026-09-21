#!/bin/sh
# Vahtii legionellalipun 0x0101 arvoa ESPHome-lokista ja ilmoittaa kun se
# muuttuu — erityisesti kun jokin nollaa sen.
#
# Käyttö:  ./watch-legionella.sh <loki> [tunnit]
# Esim.:   ./watch-legionella.sh wpc-c3-night.log 15
#
# **Hae arvoa, älä sanaa.** Ensimmäinen versio tästä etsi lokista merkkijonoa
# `legionella 0x0101:`, jota loki ei sisällä lainkaan. Vahti kävi viisitoista
# tuntia ja raportoi "ei muutosta" — ei siksi että lippu olisi pysynyt
# paikallaan vaan siksi ettei se olisi voinut havaita muutosta millään.
#
# Se on vahdin pahin vikatila: **hiljaisuus näyttää samalta kuin tulos.**
# Lokista luettavan vahdin hakuehto on siis todennettava kerran käsin
# ennen kuin sen antamaan hiljaisuuteen nojaa:
#
#     grep -ac "ex=0101" wpc-c3-night.log     # > 0, muuten ehto on väärä
#
# Sanoitus tulee dekooderista ja voi muuttua käännöksen mukana; rekisterin
# numero ei muutu. Hae siksi `ex=0101`.
#
# Lokissa on kahdenlaisia 0x0101-rivejä, ja molemmat kelpaavat:
#
#     180>680 resp ex=0101 = 256 (0x0100)     vastaus tälle solmulle
#     180>100 resp ex=0101 = 0   (0x0000)     vastaus näytölle
#
# 256 = käsittely tilattu, 0 = ei tilattu.

set -eu

LOG="${1:?anna lokitiedosto}"
TUNNIT="${2:-15}"

LOPPU=$(( $(date +%s) + TUNNIT * 3600 ))

# Hakuehdon todennus ennen kuin vahti käynnistyy — ks. yllä.
if [ "$(grep -ac "ex=0101" "$LOG" 2>/dev/null || echo 0)" -eq 0 ]; then
    echo "[vahti] lokissa ei ole yhtään ex=0101-riviä — pollaus ei ole päällä"
    exit 1
fi

arvo() {
    grep -a "ex=0101 = " "$LOG" | tail -1 | sed 's/.*ex=0101 = //; s/ .*//'
}

ALKU=$(arvo)
echo "[vahti] $LOG, lippu nyt ${ALKU}, kesto ${TUNNIT} h"

while [ "$(date +%s)" -lt "$LOPPU" ]; do
    NYT=$(arvo)
    if [ "$NYT" != "$ALKU" ]; then
        echo "[vahti] LIPPU MUUTTUI ${ALKU} -> ${NYT}"
        grep -a "ex=0101 = " "$LOG" | tail -2
        RIVI=$(grep -a "ex=0101 = $NYT" "$LOG" | head -1)
        T=$(printf '%s' "$RIVI" | cut -c2-6)
        echo "[vahti] --- väyläliikenne minuutilta $T ---"
        grep -a "^\[$T" "$LOG" \
            | grep -a "wr \|DHW tank\|Compressor\|Status code\|EVU" \
            | head -20 | cut -c1-92
        echo "[vahti] --- varaaja samaan aikaan ---"
        grep -a "DHW tank temperature" "$LOG" | tail -1
        exit 0
    fi
    sleep 60
done

echo "[vahti] aika loppui, lippu on yhä ${ALKU}"
grep -a "ex=0101 = " "$LOG" | tail -1
exit 0

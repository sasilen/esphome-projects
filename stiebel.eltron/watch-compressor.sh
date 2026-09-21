#!/bin/sh
# Vahtii kompressorin käynnistymistä ESPHome-lokista paine-erosta.
#
# Käyttö:  ./watch-compressor.sh <loki> [tunnit] [raja-bar]
# Esim.:   ./watch-compressor.sh wpc-c3-night.log 12
#
# **Miksi paine-ero eikä varaajan lämpötila.** Ensimmäinen yritys vahtia
# latauksen alkamista oli `watch-dhw.sh` matalalla rajalla — 41 °C varaajan
# ollessa 40,2. Se oli väärin: **varaaja nousee myös ilman latausta.**
# 21.9. lataus katkesi EVU-estoon 40,2 asteeseen ja lukema oli 40,7 kaksi
# tuntia myöhemmin kompressorin seistessä koko ajan. Kerrostuminen tasaantuu,
# ja anturi istuu siellä missä se tapahtuu.
#
# Matala raja siis laukeaa tasaantumisesta. Korkea raja — `watch-dhw.sh`:n
# 57 — on oikea siihen mihin se on tehty, eli valmiin legionellakäsittelyn
# erottamiseen, mutta se kertoo vasta kun kaikki on jo ohi.
#
# **Paine-ero on käynti itse.** Seisovalla koneella korkea ja matala
# tasaantuvat 0,3–0,4 baarin päähän; käyvällä ne erkanevat 17–22 baariin.
# Väliin jää tyhjää, joten raja on epäkriittinen. Sama peruste kuin
# `manager_stuck`-anturilla, ja samasta syystä: se on fysiikkaa eikä
# tilabitti, joka on tässä projektissa kerran jäätynyt päälle 29 tunniksi.
#
# **Paineet pollataan vain kun `poll_setpoints` on päällä.** Jos lukemat
# vanhenevat, vahti kertoo siitä eikä raportoi hiljaisuutta tuloksena.

set -eu

LOG="${1:?anna lokitiedosto}"
TUNNIT="${2:-12}"
RAJA="${3:-2}"

LOPPU=$(( $(date +%s) + TUNNIT * 3600 ))

if [ "$(grep -ac "'High pressure'" "$LOG" 2>/dev/null || echo 0)" -eq 0 ]; then
    echo "[vahti] lokissa ei ole painelukemia — poll_setpoints lienee pois"
    exit 1
fi

arvo() {
    grep -a "'$1'" "$LOG" | tail -1 | sed 's/.*>> //; s/ .*//'
}

echo "[vahti] $LOG, kompressori käy kun paine-ero > ${RAJA} bar, kesto ${TUNNIT} h"

VANHA=""
HP=""
LP=""
SEIS=0
while [ "$(date +%s)" -lt "$LOPPU" ]; do
    HP=$(arvo "High pressure")
    LP=$(arvo "Low pressure")
    RIVI=$(grep -a "'Low pressure'" "$LOG" | tail -1)

    if [ "$RIVI" = "$VANHA" ] && [ -n "$VANHA" ]; then
        SEIS=$(( SEIS + 1 ))
        # Kuusi tarkistusta eli kolme minuuttia ilman uutta näytettä:
        # pollausväli on kaksi, joten tämä on aito pysähdys eikä viive.
        if [ "$SEIS" -ge 6 ]; then
            echo "[vahti] PAINELUKEMAT EIVÄT PÄIVITY — en näe käyntitilaa"
            printf '%s\n' "$RIVI"
            exit 2
        fi
    else
        SEIS=0
        VANHA="$RIVI"
    fi

    if printf '%s %s %s\n' "$HP" "$LP" "$RAJA" | awk '{exit !($1 - $2 > $3)}'; then
        echo "[vahti] KOMPRESSORI KÄYNNISTYI"
        grep -a "'High pressure'\|'Low pressure'\|'Hot gas temperature'" "$LOG" | tail -6
        echo "[vahti] --- varaaja ja tilasana ---"
        grep -a "'DHW tank temperature'" "$LOG" | tail -2
        grep -a "'Element 0x4E5E'" "$LOG" | tail -2
        echo "[vahti] --- EVU ---"
        grep -a "e=0074" "$LOG" | tail -1
        exit 0
    fi
    sleep 30
done

echo "[vahti] aika loppui, kompressori ei käynnistynyt"
printf '  HP %s  LP %s\n' "${HP:-?}" "${LP:-?}"
exit 0

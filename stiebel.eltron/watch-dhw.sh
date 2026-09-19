#!/bin/sh
# Vahtii käyttövesivaraajaa ESPHome-lokista ja ilmoittaa kun se ylittää rajan.
#
# Käyttö:  ./watch-dhw.sh <loki> [raja] [tunnit]
# Esim.:   ./watch-dhw.sh wpc-c3-night.log 55 10
#
# **Varaaja on oikea signaali, ei jälkilämmityksen meno.** Meno nousee 55
# asteeseen myös tavallisessa lämmitysajossa, joten se ei erota
# legionellakäsittelyä mistään. Varaaja erottaa: tavallinen lataus pysähtyy
# 50 asteen tienoille, käsittely vie 60:n yli.
#
# **Varaaja-anturi laahaa.** 19.9. kompressori käynnistyi 19:41 ja varaaja
# lähti nousuun vasta 19:50 — yhdeksän minuuttia. Älä siis tulkitse tasaista
# varaajaa todisteeksi siitä ettei mitään ole alkamassa.

set -eu

LOG="${1:?anna lokitiedosto}"
RAJA="${2:-55}"
TUNNIT="${3:-10}"

LOPPU=$(( $(date +%s) + TUNNIT * 3600 ))

echo "[vahti] $LOG, raja ${RAJA} °C, kesto ${TUNNIT} h"

while [ "$(date +%s)" -lt "$LOPPU" ]; do
    RIVI=$(grep -a "DHW tank temperature" "$LOG" 2>/dev/null | tail -1) || true
    if [ -n "${RIVI:-}" ]; then
        ARVO=$(printf '%s\n' "$RIVI" | sed 's/.*>> //; s/ .*//')
        # sh ei osaa desimaalivertailua, joten awk tekee sen
        if printf '%s %s\n' "$ARVO" "$RAJA" | awk '{exit !($1 > $2)}'; then
            echo "[vahti] RAJA YLITTYI"
            printf '%s\n' "$RIVI"
            echo "[vahti] --- varaajan käyrä viimeisen tunnin ajalta ---"
            grep -a "DHW tank temperature" "$LOG" | tail -360 \
                | awk -F">> " '{split($0,a,"["); t=substr(a[2],1,5); v=$2+0;
                                if (t != p) { print t"  "v; p=t }}' \
                | awk 'NR%5==1'
            echo "[vahti] --- kompressorin tilanvaihdot ---"
            grep -a "'Compressor'" "$LOG" | tail -10
            exit 0
        fi
    fi
    sleep 60
done

echo "[vahti] aika loppui ilman ylitystä, raja oli ${RAJA} °C"
RIVI=$(grep -a "DHW tank temperature" "$LOG" | tail -1) || true
printf '%s\n' "${RIVI:-ei lukemia}"
exit 0

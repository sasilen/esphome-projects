#!/bin/sh
# Vahtii legionellalipun 0x0101 arvoa ESPHome-lokista ja ilmoittaa kun se
# muuttuu — erityisesti kun jokin nollaa sen.
#
# Käyttö:  ./watch-legionella.sh <loki> [tunnit]
# Esim.:   ./watch-legionella.sh wpc-c3-night.log 15
#
# **Hae arvoa, älä siirtymää.** Ensimmäinen versio etsi lokista dekooderin
# siirtymäriviä `legionella 0x0101: ON -> OFF`. Se rivi on olemassa, mutta se
# kirjoitetaan **vain kun arvo vaihtuu** — eli se puuttuu yhtä lailla silloin
# kun mitään ei ole tapahtunut kuin silloin kun vahti on rikki.
#
# Niin siinä kävikin: rivin puuttuminen luettiin todisteeksi rikkinäisestä
# hakuehdosta, vaikka se oli juuri se tulos jota vahti raportoi.
#
# Tämä versio lukee **rekisterin nykyisen arvon**, joka on lokissa joka
# tapauksessa kahden minuutin välein. Silloin "ei muutosta" ja "ei näkyvyyttä"
# eivät näytä samalta: jos arvoa ei löydy lainkaan, vahti kieltäytyy
# käynnistymästä.
#
#     grep -ac "ex=0101" wpc-c3-night.log     # > 0, muuten pollaus ei ole päällä
#
# Lokissa on kahdenlaisia 0x0101-rivejä, ja molemmat kelpaavat:
#
#     180>680 resp ex=0101 = 256 (0x0100)     vastaus tälle solmulle
#     180>100 resp ex=0101 = 0   (0x0000)     vastaus näytölle
#
# 256 = käsittely tilattu, 0 = ei tilattu.

# **Vahti tarkkailee myös lokia itseään.** Jos lokivirta kuolee, vahti
# raportoi hiljaisuutta joka näyttää samalta kuin rauhallinen väylä. Niin
# kävi 21.9.: fläshäyksen `pkill -f "esphome logs"` tappoi molemmat virrat
# ja vain toinen käynnistettiin uudelleen. Tämä poistuu virheellä jos
# tiedosto ei kasva viiteen minuuttiin.

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

KOKO=$(wc -c < "$LOG")
KUOLLUT=0

while [ "$(date +%s)" -lt "$LOPPU" ]; do
    UUSI_KOKO=$(wc -c < "$LOG")
    if [ "$UUSI_KOKO" -eq "$KOKO" ]; then
        KUOLLUT=$(( KUOLLUT + 1 ))
        if [ "$KUOLLUT" -ge 5 ]; then
            echo "[vahti] LOKI EI KASVA viiteen minuuttiin — en näe mitään"
            ls -l "$LOG"
            exit 2
        fi
    else
        KUOLLUT=0
        KOKO=$UUSI_KOKO
    fi

    NYT=$(arvo)
    if [ "$NYT" != "$ALKU" ]; then
        echo "[vahti] LIPPU MUUTTUI ${ALKU} -> ${NYT}"
        grep -a "ex=0101 = " "$LOG" | tail -2
        # Viimeinen rivi, ei ensimmäinen: loki kattaa monta vuorokautta eikä
        # aikaleimassa ole päivää, joten `head -1` osuu eiliseen samaan kellon-
        # aikaan. Siirtymä tapahtui juuri nyt, joten tuorein on oikea.
        RIVI=$(grep -a "ex=0101 = $NYT" "$LOG" | tail -1)
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

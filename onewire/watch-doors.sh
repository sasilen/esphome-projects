#!/bin/sh
# Vahtii ovikoskettimia ESPHome-lokista ja tulostaa jokaisen tapahtuman
# sitä mukaa kun niitä tulee.
#
# Käyttö:  ./watch-doors.sh <loki> [tunnit]
# Esim.:   ./watch-doors.sh onewire.log 12
#
# **Taso ja salpa tarkoittavat eri asiaa.** `taso=YES` on ovi joka on auki
# juuri sillä kierroksella; `salpa=YES` on siirtymä joka tapahtui kahden
# kierroksen välissä. Nopea käynti näkyy vain salpana, koska minuutin näyte
# ei osu auki-hetkeen. Kumpikin tulostetaan, ja rivi kertoo kumpi oli.
#
# **`322EB6` suodatetaan pois oletuksena.** Se ei ole ovi: sen kanava A
# laukeaa noin neljän minuutin välein vuorokauden ympäri eikä taso nouse
# juuri koskaan. Mukaan se tulee antamalla kolmanneksi argumentiksi `kaikki`.
#
# B-kanavat jätetään aina pois — niissä ei ole kytkintä viittä lukuun
# ottamatta, ja ne kelluvat ylhäällä joka kierroksella.

set -eu

LOG="${1:?anna lokitiedosto}"
TUNNIT="${2:-12}"
MITEN="${3:-ovet}"

LOPPU=$(( $(date +%s) + TUNNIT * 3600 ))

# Hakuehdon todennus ennen käynnistystä: vahti joka ei voi löytää mitään
# raportoi hiljaisuutta joka näyttää tulokselta. Ks. watch-legionella.sh.
if [ "$(grep -ac "ds2406" "$LOG" 2>/dev/null || echo 0)" -eq 0 ]; then
    echo "[vahti] lokissa ei ole ds2406-rivejä — väärä loki tai logger liian hiljaa"
    exit 1
fi

suodata() {
    if [ "$MITEN" = "kaikki" ]; then
        grep -a "ds2406" "$LOG" | grep -av "tulo .* B'"
    else
        grep -a "ds2406" "$LOG" | grep -av "tulo .* B'" | grep -av "322EB6"
    fi
}

# Lähtötilanne: ohita kaikki mitä lokissa jo on.
NAHTY=$(suodata | wc -l)
echo "[vahti] $LOG, ${MITEN}, kesto ${TUNNIT} h — ohitettu $NAHTY vanhaa riviä"

while [ "$(date +%s)" -lt "$LOPPU" ]; do
    NYT=$(suodata | wc -l)
    if [ "$NYT" -gt "$NAHTY" ]; then
        suodata | tail -n $(( NYT - NAHTY )) \
            | grep -a "level=YES\|latch=YES" \
            | sed "s/\[\(..:..:..\)[^]]*\]\[D\]\[ds2406[^]]*\]: /  \1  /" || true
        NAHTY=$NYT
    fi
    sleep 30
done

echo "[vahti] aika loppui"
exit 0

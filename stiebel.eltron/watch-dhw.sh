#!/bin/sh
# Vahtii käyttövesivaraajaa ESPHome-lokista ja ilmoittaa kun se ylittää rajan.
#
# Käyttö:  ./watch-dhw.sh <loki> [raja] [tunnit]
# Esim.:   ./watch-dhw.sh wpc-c3-night.log 57 10
#
# **Varaaja on oikea signaali, ei jälkilämmityksen meno.** Meno nousee 55
# asteeseen myös tavallisessa lämmitysajossa, joten se ei erota
# legionellakäsittelyä mistään.
#
# **Raja on 57, ja se johtuu asetusarvoista.** Kone lataa kahteen eri
# tavoitteeseen: `DHW eco` 50,0 päivällä ja `DHW comfort` 55,0 halvan sähkön
# tunneilla. Yön 20.9. ajo pysähtyi 54,3:een — se oli mukavuusarvon lataus
# eikä legionellayritys, mikä todettiin siitä että paneeli ja väylä sanoivat
# molemmat käsittelyn olevan pois päältä.
#
# Aiempi 52 asteen raja olisi siis lauennut **joka yö** tavallisesta
# latauksesta. Käsittelyn on ylitettävä 60, joten 57 on mukavuusarvon
# yläpuolella ja tavoitteen alapuolella.
#
# Jos asetusarvoja muutetaan, tämä raja on muutettava niiden mukana.
#
# **Älä laske rajaa latauksen alkamisen havaitsemiseksi.** Se houkuttaa:
# varaaja on 40, laita raja 41 ja tiedät heti kun lataus lähtee. Ei toimi.
# **Varaaja nousee myös ilman latausta.** 21.9. lataus katkesi EVU-estoon
# 40,2 asteeseen, ja lukema oli 40,7 kaksi tuntia myöhemmin kompressorin
# seistessä koko ajan — kerrostuminen tasaantuu, ja anturi istuu juuri
# siellä missä se tapahtuu.
#
# Tämä vahti kertoo siis vasta kun jotain on jo tapahtunut, ja se on sen
# tarkoituskin. Käynnistymistä vahtii `watch-compressor.sh` paine-erosta.
#
# **Johda raja asetusarvosta, älä siitä mitä toivot näkeväsi.** 21.9. viritin
# tämän 54 asteeseen nähdäkseni latauksen valmistuvan. Se ei olisi lauennut:
# päiväsaikaan tavoite on eco 50,0, ja lataus pysähtyi 50,7:ään tehtyään juuri
# sen mitä sen kuului. Tarkista kumpi asetusarvo on voimassa ennen kuin
# päätät mitä "valmis" tarkoittaa.
#
# **Varaaja-anturi laahaa.** 19.9. kompressori käynnistyi 19:41 ja varaaja
# lähti nousuun vasta 19:50 — yhdeksän minuuttia. Pitkän latauksen jälkeen
# viive on suurempi: 21.9. kompressori pysähtyi 12:31 ja huippu näkyi 12:48,
# eli seitsemäntoista minuuttia. Yhdeksän on alaraja eikä vakio. Älä tulkitse tasaista
# varaajaa todisteeksi siitä ettei mitään ole alkamassa.

set -eu

LOG="${1:?anna lokitiedosto}"
RAJA="${2:-57}"
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

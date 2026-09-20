#include "ds2406.h"

#include "esphome/core/helpers.h"
#include "esphome/core/log.h"

namespace esphome {
namespace ds2406 {

static const char *const TAG = "ds2406";

/// Channel Access. Sitä seuraa kaksi ohjaustavua ja luettava Channel Info.
static const uint8_t DS2406_COMMAND_CHANNEL_ACCESS = 0xF5;

/// Channel Control Byte 2 on varattu tulevalle käytölle ja **on aina 0xFF**.
static const uint8_t DS2406_CONTROL_BYTE_2 = 0xFF;

/// Channel Control Byte 1:n ylin bitti. Nollaa valitun kanavan
/// tapahtumasalvan — ja tekee sen ennen kuin Channel Info lähetetään.
static const uint8_t DS2406_CONTROL_ALR = 0x80;

void DS2406BinarySensor::setup() {
  if (!this->check_address_or_index_())
    this->mark_failed();
}

void DS2406BinarySensor::update() {
  if (this->is_failed())
    return;

  uint8_t info;
  {
    InterruptLock lock;
    // **Luku tehdään aina ALR=0:lla.** `ALR=1` nollaa valitun kanavan salvan
    // *ennen* kuin Channel Info lähetetään, joten sillä luettu salpa on aina
    // nolla — myös silloin kun tulo oikeasti liikkui. Se todettiin ovesta
    // joka avattiin ja suljettiin kierrosten välissä.
    //
    // send_command_ tekee resetin, MATCH ROMin ja käskyn yhdellä kutsulla.
    if (!this->send_command_(DS2406_COMMAND_CHANNEL_ACCESS)) {
      this->status_set_warning();
      return;
    }
    this->bus_->write8(this->control_byte_);
    this->bus_->write8(DS2406_CONTROL_BYTE_2);
    info = this->bus_->read8();
  }

  // Nollaus on oma käskynsä. Se tehdään vasta kun salpa on luettu, ja vain
  // jos salpaa käytetään — muuten se hävittäisi tiedon jota kukaan ei lukenut.
  if (this->use_latch_) {
    InterruptLock lock;
    if (this->send_command_(DS2406_COMMAND_CHANNEL_ACCESS)) {
      this->bus_->write8(this->control_byte_ | DS2406_CONTROL_ALR);
      this->bus_->write8(DS2406_CONTROL_BYTE_2);
      this->bus_->read8();  // vastaus ei kiinnosta, nollaus tapahtui jo
    }
  }

  // Vaiennut väylä lukee kaikki ykköset. Se ei ole kelvollinen Channel Info:
  // bitti 6 kertoo kanavien määrän ja bitti 7 syötön, eivätkä ne molemmat ole
  // ykkösiä samaan aikaan silloin kun laite oikeasti vastaa.
  if (info == 0xFF) {
    ESP_LOGW(TAG, "'%s': no response (0xFF)", this->get_name().c_str());
    this->status_set_warning();
    return;
  }

  // CHANNEL INFO BYTE
  //  b7 syöttö · b6 kanavien määrä · b5 PIOB salpa · b4 PIOA salpa
  //  b3 PIOB taso · b2 PIOA taso · b1 PIOB Q · b0 PIOA Q
  const bool is_b = (this->control_byte_ & 0x08) != 0;  // CHS1 → PIOB
  const bool level = is_b ? ((info & 0x08) != 0) : ((info & 0x04) != 0);
  const bool latch = is_b ? ((info & 0x20) != 0) : ((info & 0x10) != 0);

  // **Salpa muistaa muutoksen jota pollaus ei ehtinyt nähdä.** Se luetaan yllä
  // ALR=0:lla ja nollataan erillisellä käskyllä, jolloin seuraava kierros
  // vastaa kysymykseen "liikkuiko tämän jälkeen". Julkaistu tila on silloin
  // *päällä nyt tai ollut päällä välissä*.
  const bool state = this->use_latch_ ? (level || latch) : level;

  ESP_LOGD(TAG, "'%s': info=0x%02X level=%s latch=%s -> %s", this->get_name().c_str(), info, YESNO(level),
           YESNO(latch), YESNO(state));
  this->status_clear_warning();
  this->publish_state(state);
}

void DS2406BinarySensor::dump_config() {
  LOG_BINARY_SENSOR("", "DS2406 Binary Sensor", this);
  LOG_ONE_WIRE_DEVICE(this);
  ESP_LOGCONFIG(TAG, "  Channel: %s", (this->control_byte_ & 0x08) != 0 ? "B" : "A");
  ESP_LOGCONFIG(TAG, "  Latch: %s (control byte 0x%02X)", ONOFF(this->use_latch_), this->control_byte_);
  LOG_UPDATE_INTERVAL(this);
}

}  // namespace ds2406
}  // namespace esphome

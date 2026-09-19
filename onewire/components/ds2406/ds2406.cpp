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
    // send_command_ tekee resetin, MATCH ROMin ja käskyn yhdellä kutsulla.
    if (!this->send_command_(DS2406_COMMAND_CHANNEL_ACCESS)) {
      this->status_set_warning();
      return;
    }
    this->bus_->write8(this->control_byte_);
    this->bus_->write8(DS2406_CONTROL_BYTE_2);
    info = this->bus_->read8();
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
  const bool level = (this->control_byte_ & 0x08) != 0 ? ((info & 0x08) != 0)   // CHS1 → PIOB
                                                       : ((info & 0x04) != 0);  // muuten PIOA

  ESP_LOGD(TAG, "'%s': info=0x%02X level=%s", this->get_name().c_str(), info, YESNO(level));
  this->status_clear_warning();
  this->publish_state(level);
}

void DS2406BinarySensor::dump_config() {
  LOG_BINARY_SENSOR("", "DS2406 Binary Sensor", this);
  LOG_ONE_WIRE_DEVICE(this);
  ESP_LOGCONFIG(TAG, "  Channel: %s", (this->control_byte_ & 0x08) != 0 ? "B" : "A");
  LOG_UPDATE_INTERVAL(this);
}

}  // namespace ds2406
}  // namespace esphome

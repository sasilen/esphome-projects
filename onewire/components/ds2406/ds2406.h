#pragma once

#include "esphome/components/binary_sensor/binary_sensor.h"
#include "esphome/components/one_wire/one_wire.h"
#include "esphome/core/component.h"

namespace esphome {
namespace ds2406 {

/// DS2406:n PIO-tulon luku binäärianturina.
///
/// Vain luku. Kirjoitusta ei ole tarkoituksella: Channel Access osaa myös
/// ajaa lähtöä, ja tämä verkko on rakennettu ovikoskettimille.
class DS2406BinarySensor : public PollingComponent,
                           public binary_sensor::BinarySensor,
                           public one_wire::OneWireDevice {
 public:
  void setup() override;
  void update() override;
  void dump_config() override;
  float get_setup_priority() const override { return setup_priority::DATA; }

  /// Channel Control Byte 1, valmiiksi laskettuna kanavan mukaan.
  void set_control_byte(uint8_t b) { this->control_byte_ = b; }

 protected:
  uint8_t control_byte_{0x44};
};

}  // namespace ds2406
}  // namespace esphome

import esphome.codegen as cg
from esphome.components import binary_sensor, one_wire
import esphome.config_validation as cv
from esphome.types import ConfigType

ds2406_ns = cg.esphome_ns.namespace("ds2406")

DS2406BinarySensor = ds2406_ns.class_(
    "DS2406BinarySensor",
    cg.PollingComponent,
    binary_sensor.BinarySensor,
    one_wire.OneWireDevice,
)

CONF_CHANNEL = "channel"
CONF_LATCH = "latch"

# Channel Control Byte 1:  ALR IM TOG IC CHS1 CHS0 CRC1 CRC0
#   ALR = 0   **aina**: luku ei saa nollata salpaa, koska nollaus tapahtuu
#             ennen raportointia. `latch: true` nollaa sen erillisellä
#             käskyllä vasta kun salpa on luettu.
#   IM  = 1   **lukutila** — tämä bitti erottaa luvun kirjoituksesta
#   TOG = 0   kiinteä tila
#   IC  = 0
#   CHS = 01 kanava A, 10 kanava B
#   CRC = 00 ei CRC:tä
CHANNELS = {
    "A": 0x44,
    "B": 0x48,
}

CONFIG_SCHEMA = (
    binary_sensor.binary_sensor_schema(DS2406BinarySensor)
    .extend(
        {
            cv.Optional(CONF_CHANNEL, default="A"): cv.enum(CHANNELS, upper=True),
            # Ota tapahtumasalpa mukaan tilaan. Piiri muistaa muutoksen jota
            # pollaus ei ehtinyt nähdä. Salpa luetaan ALR=0:lla ja nollataan
            # erillisellä käskyllä, joten tila tarkoittaa *päällä nyt tai
            # ollut välissä*.
            cv.Optional(CONF_LATCH, default=False): cv.boolean,
        }
    )
    .extend(one_wire.one_wire_device_schema())
    .extend(cv.polling_component_schema("60s"))
)


async def to_code(config: ConfigType) -> None:
    var = await binary_sensor.new_binary_sensor(config)
    await cg.register_component(var, config)
    await one_wire.register_one_wire_device(var, config)

    # **`cv.enum` palauttaa avaimen, ei arvoa.** Se on merkkijonon aliluokka
    # jolla on `.enum_value`, joten `config[CONF_CHANNEL]` on "A" eikä 0x44.
    # Haku taulukosta on selvempi kuin sisäiseen attribuuttiin nojaaminen.
    cg.add(var.set_control_byte(CHANNELS[config[CONF_CHANNEL]]))
    cg.add(var.set_use_latch(config[CONF_LATCH]))

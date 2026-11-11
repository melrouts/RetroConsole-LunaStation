#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_arduino_version.h>
#include <esp_sleep.h>
#include <driver/gpio.h>
#include <Adafruit_NeoPixel.h>
#include <string.h>
#include "controller_power.h"

namespace {

constexpr uint8_t ESPNOW_CHANNEL = 1;
constexpr uint32_t PACKET_MAGIC = 0x4c554e41;
constexpr uint32_t STATUS_MAGIC = 0x4c555354;
constexpr uint8_t PACKET_VERSION = 1;
constexpr uint32_t MATRIX_FRAME_MS = ControllerPower::FRAME_MS;
constexpr uint32_t STATUS_TIMEOUT_MS = 5000;
constexpr uint32_t SEND_INTERVAL_MS = 1000;
constexpr uint32_t LED_PULSE_MS = 100;
constexpr uint8_t LED_PIN = 2;
constexpr uint8_t LED_ON = HIGH;
constexpr uint8_t LED_OFF = LOW;
constexpr uint8_t MATRIX_PIN = 23;
constexpr uint8_t MATRIX_WIDTH = 4;
constexpr uint8_t MATRIX_HEIGHT = 4;
constexpr uint8_t MATRIX_PIXELS = MATRIX_WIDTH * MATRIX_HEIGHT;
constexpr uint8_t MATRIX_BRIGHTNESS = 24;
constexpr uint8_t DISPLAY_STOP = 0xff;
// The Tang releases held buttons after 250 ms without a packet.
constexpr uint32_t BUTTON_REPEAT_MS = 100;

enum class Direction : uint8_t {
    Stop,
    Down,
    Left,
    Right,
    Up,
};

enum class SendReason : uint8_t {
    Counter,
    ButtonChange,
    ButtonHold,
};

struct ButtonPin {
    uint8_t pin;
    const char* name;
};

// The array index is the bit in the packet's buttons field (Tang held_mask order).
constexpr ButtonPin buttonPins[] = {
    {27, "LEFT"},
    {32, "THRUST"},
    {25, "RIGHT"},
    {4, "MENU"},
};
constexpr size_t BUTTON_COUNT = sizeof(buttonPins) / sizeof(buttonPins[0]);
static_assert(BUTTON_COUNT <= 4, "the buttons field carries four bits");

const uint8_t broadcastAddress[] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
uint8_t transmitterAddress[6]{};
Adafruit_NeoPixel matrix(MATRIX_PIXELS, MATRIX_PIN, NEO_GRB + NEO_KHZ800);

const uint16_t digitMasks[10] = {
    0x6996, 0x2627, 0xE16F, 0xE16E, 0x99F1,
    0xF86E, 0x68E6, 0xF124, 0xF9F9, 0x6971,
};

struct __attribute__((packed)) CounterPacket {
    uint32_t magic;
    uint8_t version;
    uint8_t buttons;
    uint32_t sequence;
    uint32_t counter;
};

struct __attribute__((packed)) StatusPacket {
    uint32_t magic;
    uint8_t version;
    uint8_t direction;
    uint8_t speed;
    uint32_t sequence;
};

portMUX_TYPE statusMux = portMUX_INITIALIZER_UNLOCKED;
StatusPacket latestStatus{};
bool statusAvailable = false;
bool statusUpdated = false;
uint32_t statusReceivedAt = 0;
uint32_t lastMatrixFrameMs = 0;
uint8_t animationFrame = 0;
uint8_t displayedValue = 0;
uint8_t lastDisplayedValue = DISPLAY_STOP;

void renderMatrix(uint8_t value) {
    if (value == lastDisplayedValue) {
        return;
    }

    matrix.clear();
    const uint32_t color = value == DISPLAY_STOP
                               ? matrix.Color(0, 0, MATRIX_BRIGHTNESS)
                               : matrix.Color(0, MATRIX_BRIGHTNESS, 0);

    if (value == DISPLAY_STOP) {
        for (uint8_t y = 1; y <= 2; ++y) {
            for (uint8_t x = 1; x <= 2; ++x) {
                const uint8_t column = (y & 1) ? MATRIX_WIDTH - 1 - x : x;
                matrix.setPixelColor(y * MATRIX_WIDTH + column, color);
            }
        }
    } else {
        const uint16_t mask = digitMasks[value % 10];
        for (uint8_t y = 0; y < MATRIX_HEIGHT; ++y) {
            for (uint8_t x = 0; x < MATRIX_WIDTH; ++x) {
                const uint8_t bit = (MATRIX_HEIGHT - 1 - y) * MATRIX_WIDTH +
                                    (MATRIX_WIDTH - 1 - x);
                if (mask & (1u << bit)) {
                    const uint8_t column = (y & 1) ? MATRIX_WIDTH - 1 - x : x;
                    matrix.setPixelColor(y * MATRIX_WIDTH + column, color);
                }
            }
        }
    }

    matrix.show();
    lastDisplayedValue = value;
}

uint8_t pixelIndex(uint8_t x, uint8_t y) {
    const uint8_t column = (y & 1) ? MATRIX_WIDTH - 1 - x : x;
    return y * MATRIX_WIDTH + column;
}

void receivePacket(const uint8_t* data, int length) {
    if (length != sizeof(StatusPacket)) {
        return;
    }

    StatusPacket packet;
    memcpy(&packet, data, sizeof(packet));
    if (packet.magic != STATUS_MAGIC ||
        packet.version != PACKET_VERSION ||
        packet.direction > static_cast<uint8_t>(Direction::Up) ||
        packet.speed > 3) {
        return;
    }

    portENTER_CRITICAL(&statusMux);
    latestStatus = packet;
    statusAvailable = true;
    statusUpdated = true;
    statusReceivedAt = millis();
    portEXIT_CRITICAL(&statusMux);
}

#if ESP_ARDUINO_VERSION_MAJOR >= 3
void onDataReceived(const esp_now_recv_info_t* info, const uint8_t* data, int length) {
    (void)info;
    receivePacket(data, length);
}
#else
void onDataReceived(const uint8_t* mac, const uint8_t* data, int length) {
    (void)mac;
    receivePacket(data, length);
}
#endif

void renderStatus(const StatusPacket& status, uint8_t frame) {
    matrix.clear();
    if (status.direction == static_cast<uint8_t>(Direction::Stop) ||
        status.speed == 0) {
        const uint32_t color = matrix.Color(0, 0, MATRIX_BRIGHTNESS);
        for (uint8_t x = 0; x < MATRIX_WIDTH; ++x) {
            matrix.setPixelColor(pixelIndex(x, 1), color);
        }
        matrix.show();
        return;
    }

    uint32_t color;
    if (status.direction == static_cast<uint8_t>(Direction::Up) || status.speed >= 3) {
        color = matrix.Color(MATRIX_BRIGHTNESS, 0, 0);
    } else if (status.speed == 2) {
        color = matrix.Color(MATRIX_BRIGHTNESS, MATRIX_BRIGHTNESS / 2, 0);
    } else {
        color = matrix.Color(0, MATRIX_BRIGHTNESS, 0);
    }

    const uint8_t position = frame % MATRIX_WIDTH;
    if (status.direction == static_cast<uint8_t>(Direction::Down)) {
        for (uint8_t x = 1; x <= 2; ++x) {
            matrix.setPixelColor(pixelIndex(x, position), color);
        }
    } else if (status.direction == static_cast<uint8_t>(Direction::Up)) {
        for (uint8_t x = 1; x <= 2; ++x) {
            matrix.setPixelColor(pixelIndex(x, MATRIX_HEIGHT - 1 - position), color);
        }
    } else if (status.direction == static_cast<uint8_t>(Direction::Left)) {
        for (uint8_t y = 1; y <= 2; ++y) {
            matrix.setPixelColor(pixelIndex(position, y), color);
        }
    } else {
        for (uint8_t y = 1; y <= 2; ++y) {
            matrix.setPixelColor(pixelIndex(MATRIX_WIDTH - 1 - position, y), color);
        }
    }
    matrix.show();
}

uint32_t sequence = 0;
uint32_t counter = 0;
uint32_t lastCounter = 0;
uint32_t lastSendMs = 0;
uint32_t lastPacketMs = 0;
uint8_t buttonState = 0;
uint8_t rawButtons = 0;
uint8_t heldButtons = 0;
ControllerPower::Buttons buttons;
ControllerPower::State powerState;
bool radioReady = false;
uint32_t lastRadioRetryMs = 0;
bool transmitting = false;
bool ledOn = false;
uint32_t ledOffAt = 0;
char commandBuffer[32];
size_t commandLength = 0;
bool commandOverflow = false;
bool skipLineFeed = false;
int lastSendError = 0;

bool initializeEspNow() {
    if (!WiFi.mode(WIFI_STA)) {
        return false;
    }
    if (esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
        return false;
    }
    if (esp_wifi_get_mac(WIFI_IF_STA, transmitterAddress) != ESP_OK) {
        return false;
    }
    if (esp_now_init() != ESP_OK) {
        return false;
    }

    esp_now_peer_info_t peer{};
    memcpy(peer.peer_addr, broadcastAddress, sizeof(broadcastAddress));
    peer.channel = ESPNOW_CHANNEL;
    peer.encrypt = false;
    if (esp_now_add_peer(&peer) != ESP_OK) {
        return false;
    }
    return esp_now_register_recv_cb(onDataReceived) == ESP_OK;
}

void formatButtons(uint8_t mask, char* text, size_t size) {
    size_t length = 0;
    text[0] = '\0';
    for (size_t i = 0; i < BUTTON_COUNT && length < size; ++i) {
        if (mask & (1u << i)) {
            length += snprintf(text + length, size - length, "%s%s",
                               length > 0 ? "+" : "", buttonPins[i].name);
        }
    }
    if (length == 0) {
        snprintf(text, size, "none");
    }
}

bool updateButtons(uint32_t now) {
    uint8_t raw = 0;
    for (size_t i = 0; i < BUTTON_COUNT; ++i) {
        if (digitalRead(buttonPins[i].pin) == LOW) {
            raw |= 1u << i;
        }
    }

    const uint8_t previous = buttonState;
    rawButtons = raw;
    heldButtons = buttons.update(raw, now);
    buttonState = powerState.update(heldButtons, now);
    powerState.released(rawButtons, heldButtons);
    return buttonState != previous;
}

void sendPacket(uint32_t now, SendReason reason) {
    if (!radioReady) {
        return;
    }
    const CounterPacket packet{
        PACKET_MAGIC,
        PACKET_VERSION,
        buttonState,
        sequence++,
        lastCounter,
    };
    lastPacketMs = now;
    digitalWrite(LED_PIN, LED_ON);
    ledOn = true;
    ledOffAt = now + LED_PULSE_MS;

    const esp_err_t result = esp_now_send(
        broadcastAddress,
        reinterpret_cast<const uint8_t*>(&packet),
        sizeof(packet));
    lastSendError = result == ESP_OK ? 0 : result;
    if (result != ESP_OK) {
        Serial.printf("ERROR: esp_now_send returned %d\n", result);
        return;
    }

    char names[32];
    formatButtons(packet.buttons, names, sizeof(names));
    if (reason == SendReason::Counter) {
        Serial.printf("TX seq=%lu counter=%lu buttons=0x%02X %s\n",
                      static_cast<unsigned long>(packet.sequence),
                      static_cast<unsigned long>(packet.counter),
                      packet.buttons,
                      names);
    } else {
        Serial.printf("TX seq=%lu buttons=0x%02X %s%s\n",
                      static_cast<unsigned long>(packet.sequence),
                      packet.buttons,
                      names,
                      reason == SendReason::ButtonHold ? " (hold)" : "");
    }
}

void renderPowerTransition(uint32_t now) {
    const bool waking = powerState.mode() == ControllerPower::Mode::Waking ||
                        powerState.mode() == ControllerPower::Mode::WaitWakeRelease;
    const uint8_t frame = powerState.frame(now);
    const uint8_t stage = waking ? 3 - frame : frame;
    matrix.clear();
    for (uint8_t y = 0; y < MATRIX_HEIGHT; ++y) {
        for (uint8_t x = 0; x < MATRIX_WIDTH; ++x) {
            const bool centre = x >= 1 && x <= 2 && y >= 1 && y <= 2;
            if (stage == 0 || (centre && stage < 3)) {
                const uint8_t level = stage == 2 ? MATRIX_BRIGHTNESS / 3
                                               : MATRIX_BRIGHTNESS;
                matrix.setPixelColor(pixelIndex(x, y), matrix.Color(0, 0, level));
            }
        }
    }
    matrix.show();
    lastDisplayedValue = DISPLAY_STOP - 1;
}

void sleepController() {
    // Classic ESP32 ext1 has ALL_LOW, not ANY_LOW. GPIO light-sleep wake lets
    // each active-low button wake independently, with the existing pull-ups.
    esp_err_t result = ESP_OK;
    for (const ButtonPin& button : buttonPins) {
        const esp_err_t pinResult = gpio_wakeup_enable(
            static_cast<gpio_num_t>(button.pin), GPIO_INTR_LOW_LEVEL);
        if (pinResult != ESP_OK) {
            result = pinResult;
        }
    }
    if (result == ESP_OK) {
        result = esp_sleep_enable_gpio_wakeup();
    }

    matrix.clear();
    matrix.show();
    digitalWrite(LED_PIN, LED_OFF);
    ledOn = false;
    esp_now_deinit();
    radioReady = false;
    WiFi.mode(WIFI_OFF);
    portENTER_CRITICAL(&statusMux);
    statusAvailable = false;
    statusUpdated = false;
    portEXIT_CRITICAL(&statusMux);
    Serial.println("SLEEP: radio off; press any button to wake");
    Serial.flush();
    if (result == ESP_OK) {
        result = esp_light_sleep_start();
    }
    esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_GPIO);
    for (const ButtonPin& button : buttonPins) {
        gpio_wakeup_disable(static_cast<gpio_num_t>(button.pin));
    }
    if (result != ESP_OK) {
        Serial.printf("ERROR: light sleep returned %d\n", result);
    }

    buttons = ControllerPower::Buttons{};
    heldButtons = rawButtons = buttonState = 0;
    radioReady = initializeEspNow();
    lastRadioRetryMs = millis();
    lastSendMs = millis();
    powerState.wake(millis());
    lastMatrixFrameMs = millis() - MATRIX_FRAME_MS;
    if (radioReady) {
        sendPacket(millis(), SendReason::ButtonChange);
    } else {
        Serial.println("ERROR: ESP-NOW restore failed; retrying");
    }
    Serial.println("WAKE: release all buttons to resume controls");
}

void handleCommand(const char* command) {
    if (commandOverflow) {
        commandOverflow = false;
        Serial.println("ERROR: command too long");
    } else if (strcmp(command, "start") == 0) {
        transmitting = true;
        lastSendMs = millis() - SEND_INTERVAL_MS;
        lastSendError = 0;
        Serial.println("Counter started; button transmission is always active");
    } else if (strcmp(command, "stop") == 0) {
        transmitting = false;
        Serial.println("Counter stopped; button transmission is still active");
    } else if (strcmp(command, "reset") == 0) {
        counter = 0;
        lastCounter = 0;
        displayedValue = 0;
        lastSendError = 0;
        if (transmitting) {
            renderMatrix(displayedValue);
        }
        Serial.println("Counter reset");
    } else if (strcmp(command, "status") == 0) {
        char names[32];
        formatButtons(buttonState, names, sizeof(names));
        Serial.printf("status=%s seq=%lu counter=%lu channel=%u buttons=0x%02X %s\n",
                      transmitting ? "TX" : "STOPPED",
                      static_cast<unsigned long>(sequence),
                      static_cast<unsigned long>(counter),
                      ESPNOW_CHANNEL,
                      buttonState,
                      names);
    } else if (strcmp(command, "help") == 0) {
        Serial.println("Commands: start, stop, reset, status, help");
    } else if (command[0] != '\0') {
        Serial.printf("Unknown command: %.60s\n", command);
    }
    commandLength = 0;
}

void readSerialCommands() {
    while (Serial.available() > 0) {
        const char character = static_cast<char>(Serial.read());
        if (character == '\r' || character == '\n') {
            if (character == '\n' && skipLineFeed) {
                skipLineFeed = false;
                continue;
            }
            skipLineFeed = character == '\r';
            commandBuffer[commandLength] = '\0';
            handleCommand(commandBuffer);
        } else if (character == '\b' || character == 0x7f) {
            skipLineFeed = false;
            if (commandLength > 0) {
                --commandLength;
                Serial.print(" \b");
            }
        } else if (commandLength < sizeof(commandBuffer) - 1) {
            skipLineFeed = false;
            commandBuffer[commandLength++] = character;
        } else {
            skipLineFeed = false;
            commandOverflow = true;
        }
    }
}

}  // namespace

void setup() {
    Serial.begin(115200);
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LED_OFF);
    for (const ButtonPin& button : buttonPins) {
        pinMode(button.pin, INPUT_PULLUP);
    }
    matrix.begin();
    matrix.setBrightness(MATRIX_BRIGHTNESS);
    matrix.clear();
    matrix.show();
    lastDisplayedValue = DISPLAY_STOP - 1;
    delay(500);

    if (!initializeEspNow()) {
        Serial.println("ERROR: ESP-NOW init failed");
        while (true) {
            delay(1000);
        }
    }
    radioReady = true;

    Serial.printf("TX ready, MAC=%02X:%02X:%02X:%02X:%02X:%02X\n",
                  transmitterAddress[0], transmitterAddress[1], transmitterAddress[2],
                  transmitterAddress[3], transmitterAddress[4], transmitterAddress[5]);
    Serial.println("ESP-NOW channel 1; counter stopped until commanded");
    Serial.print("Buttons to GND:");
    for (const ButtonPin& button : buttonPins) {
        Serial.printf(" %s=IO%u", button.name, button.pin);
    }
    Serial.println();
    Serial.printf("Buttons are sent on change and every %lu ms while held\n",
                  static_cast<unsigned long>(BUTTON_REPEAT_MS));
    Serial.println("TX means queued locally, not confirmed by a receiver");
    Serial.println("Hold MENU for 2 seconds to sleep; any button wakes");
    Serial.println("Commands: start, stop, reset, status, help");
    renderMatrix(DISPLAY_STOP);
}

void loop() {
    const uint32_t now = millis();
    const ControllerPower::Mode previousMode = powerState.mode();
    const bool changed = updateButtons(now);
    if (powerState.mode() != previousMode) {
        lastMatrixFrameMs = now - MATRIX_FRAME_MS;
    }
    if (!radioReady && now - lastRadioRetryMs >= SEND_INTERVAL_MS) {
        lastRadioRetryMs = now;
        esp_now_deinit();
        WiFi.mode(WIFI_OFF);
        radioReady = initializeEspNow();
        if (radioReady) {
            sendPacket(now, SendReason::ButtonChange);
        }
    }
    if (changed || (previousMode == ControllerPower::Mode::Active &&
                    powerState.mode() == ControllerPower::Mode::Entering)) {
        sendPacket(now, SendReason::ButtonChange);
    } else if (buttonState != 0 && now - lastPacketMs >= BUTTON_REPEAT_MS) {
        sendPacket(now, SendReason::ButtonHold);
    }

    if (powerState.mode() != ControllerPower::Mode::Active) {
        if (now - lastMatrixFrameMs >= MATRIX_FRAME_MS) {
            lastMatrixFrameMs = now;
            renderPowerTransition(now);
        }
        if (ledOn && static_cast<int32_t>(now - ledOffAt) >= 0) {
            digitalWrite(LED_PIN, LED_OFF);
            ledOn = false;
        }
        if (powerState.shouldSleep(rawButtons, heldButtons)) {
            sleepController();
        }
        delay(1);
        return;
    }
    readSerialCommands();

    if (now - lastMatrixFrameMs >= MATRIX_FRAME_MS) {
        lastMatrixFrameMs = now;
        StatusPacket status{};
        bool showStatus = false;
        bool newStatus = false;
        portENTER_CRITICAL(&statusMux);
        if (statusAvailable) {
            status = latestStatus;
            // A packet can arrive after `now` was sampled; a negative age is fresh.
            showStatus = static_cast<int32_t>(now - statusReceivedAt) <=
                         static_cast<int32_t>(STATUS_TIMEOUT_MS);
        }
        newStatus = statusUpdated;
        statusUpdated = false;
        portEXIT_CRITICAL(&statusMux);

        if (showStatus) {
            renderStatus(status, animationFrame++);
            lastDisplayedValue = DISPLAY_STOP - 1;
        } else {
            renderMatrix(transmitting ? displayedValue : DISPLAY_STOP);
        }
        if (newStatus) {
            static const char* const directionNames[] = {
                "STOP", "DOWN", "LEFT", "RIGHT", "UP",
            };
            Serial.printf("RX STATUS seq=%lu direction=%s speed=%u\n",
                          static_cast<unsigned long>(status.sequence),
                          directionNames[status.direction],
                          status.speed);
        }
    }

    if (ledOn && static_cast<int32_t>(now - ledOffAt) >= 0) {
        digitalWrite(LED_PIN, LED_OFF);
        ledOn = false;
    }
    if (!transmitting || now - lastSendMs < SEND_INTERVAL_MS) {
        return;
    }
    lastSendMs = now;
    lastCounter = counter++;
    displayedValue = static_cast<uint8_t>(lastCounter % 10);
    renderMatrix(displayedValue);
    sendPacket(now, SendReason::Counter);
}

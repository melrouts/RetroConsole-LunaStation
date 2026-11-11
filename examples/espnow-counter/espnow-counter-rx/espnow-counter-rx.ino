#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_arduino_version.h>
#include <atomic>
// The legacy driver is shared by Arduino-ESP32 cores 2.x and 3.x.
#include <driver/i2s.h>
#include <string.h>

#include "button_mapping.h"
#include "controller_arbiter.h"
#include "game_audio.h"
#include "startup_chime.h"

namespace {

constexpr uint8_t ESPNOW_CHANNEL = 1;
constexpr uint32_t PACKET_MAGIC = 0x4c554e41;
constexpr uint32_t STATUS_MAGIC = 0x4c555354;
constexpr uint8_t PACKET_VERSION = 1;
constexpr uint32_t STATUS_MIN_INTERVAL_MS = 1000;
constexpr uint32_t STATUS_MAX_INTERVAL_MS = 3000;
constexpr uint32_t LED_PULSE_MS = 100;
constexpr uint8_t LED_PIN = 2;
constexpr uint8_t LED_ON = HIGH;
constexpr uint8_t LED_OFF = LOW;
constexpr uint8_t TANG_RX_PIN = 16;
constexpr uint8_t TANG_TX_PIN = 17;
constexpr uint8_t AUDIO_BCLK_PIN = 32;
constexpr uint8_t AUDIO_LRC_PIN = 25;
constexpr uint8_t AUDIO_DIN_PIN = 22;
constexpr i2s_port_t AUDIO_PORT = I2S_NUM_0;
constexpr size_t AUDIO_BUFFER_FRAMES = 128;

enum class Direction : uint8_t {
    Stop,
    Down,
    Left,
    Right,
    Up,
};

const uint8_t broadcastAddress[] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
uint8_t receiverAddress[6]{};

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

portMUX_TYPE packetMux = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE audioLinkMux = portMUX_INITIALIZER_UNLOCKED;

struct ReceivedPacket {
    uint8_t mac[6];
    CounterPacket packet;
};

constexpr size_t PACKET_QUEUE_SIZE = 16;
ReceivedPacket packetQueue[PACKET_QUEUE_SIZE];
size_t packetQueueHead = 0;
size_t packetQueueCount = 0;
uint32_t packetQueueDropped = 0;
GameAudioLink gameAudioLink;
ControllerArbiter arbiter;
uint8_t forwardedButtons = 0;
bool ledOn = false;
uint32_t ledOffAt = 0;
uint32_t packetCount = 0;
uint32_t lastSequence = 0;
uint32_t lastCounter = 0;
uint8_t lastButtons = 0;
uint32_t statusSequence = 0;
uint32_t nextStatusAt = 0;
char commandBuffer[32];
size_t commandLength = 0;
bool skipLineFeed = false;
TaskHandle_t audioTaskHandle = nullptr;
std::atomic<bool> audioFailed{false};
std::atomic<bool> audioDemoRequested{false};
std::atomic<uint8_t> musicVolume{7};
std::atomic<uint8_t> effectsVolume{7};

void uninstallAudio() {
    const esp_err_t result = i2s_driver_uninstall(AUDIO_PORT);
    if (result != ESP_OK) {
        Serial.printf("ERROR: I2S uninstall failed: %s\n", esp_err_to_name(result));
    }
}

void audioTask(void*) {
    StartupChime chime;
    GameAudio gameAudio;
    GameAudioDemo demo;
    int16_t samples[AUDIO_BUFFER_FRAMES * 2];
    for (;;) {
        if (!chime.playing() && ulTaskNotifyTake(pdTRUE, 0) > 0) {
            chime.play();
            Serial.println("AUDIO: playing startup chime");
        }
        if (audioDemoRequested.exchange(false)) {
            demo.start();
        }
        GameAudioState state;
        if (!demo.next(state, AUDIO_BUFFER_FRAMES)) {
            GameAudioLink linkSnapshot;
            portENTER_CRITICAL(&audioLinkMux);
            linkSnapshot = gameAudioLink;
            portEXIT_CRITICAL(&audioLinkMux);
            state = linkSnapshot.state(millis());
        }
        gameAudio.setVolumes(musicVolume.load(), effectsVolume.load());
        gameAudio.setState(state);
        const bool wasPlaying = chime.playing();
        chime.render(samples, AUDIO_BUFFER_FRAMES);
        gameAudio.mix(samples, AUDIO_BUFFER_FRAMES);
        size_t written = 0;
        const esp_err_t result = i2s_write(
            AUDIO_PORT, samples, sizeof(samples), &written, pdMS_TO_TICKS(100));
        if (result != ESP_OK || written != sizeof(samples)) {
            audioFailed.store(true);
            Serial.printf("ERROR: I2S write failed: %s, bytes=%u/%u; audio disabled\n",
                          esp_err_to_name(result), static_cast<unsigned>(written),
                          static_cast<unsigned>(sizeof(samples)));
            uninstallAudio();
            // Keep the notification handle valid, but never retry a failed driver.
            vTaskSuspend(nullptr);
        }
        if (wasPlaying && !chime.playing()) {
            Serial.println("AUDIO: chime queued to I2S");
        }
        // Continue sending zero samples when idle, rather than replaying old DMA data.
    }
}

bool initializeAudio() {
    i2s_config_t config{};
    config.mode = static_cast<i2s_mode_t>(I2S_MODE_MASTER | I2S_MODE_TX);
    config.sample_rate = StartupChime::SAMPLE_RATE;
    config.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
    config.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;
    config.communication_format = I2S_COMM_FORMAT_STAND_I2S;
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    config.dma_desc_num = 8;
    config.dma_frame_num = AUDIO_BUFFER_FRAMES;
#else
    config.dma_buf_count = 8;
    config.dma_buf_len = AUDIO_BUFFER_FRAMES;
#endif
    config.tx_desc_auto_clear = true;
    esp_err_t result = i2s_driver_install(AUDIO_PORT, &config, 0, nullptr);
    if (result != ESP_OK) {
        Serial.printf("ERROR: I2S init failed: %s; receiver continues without audio\n",
                      esp_err_to_name(result));
        return false;
    }

    i2s_pin_config_t pins{};
    pins.mck_io_num = I2S_PIN_NO_CHANGE;
    pins.bck_io_num = AUDIO_BCLK_PIN;
    pins.ws_io_num = AUDIO_LRC_PIN;
    pins.data_out_num = AUDIO_DIN_PIN;
    pins.data_in_num = I2S_PIN_NO_CHANGE;
    result = i2s_set_pin(AUDIO_PORT, &pins);
    if (result == ESP_OK) {
        result = i2s_zero_dma_buffer(AUDIO_PORT);
    }
    if (result != ESP_OK) {
        Serial.printf("ERROR: I2S setup failed: %s; receiver continues without audio\n",
                      esp_err_to_name(result));
        uninstallAudio();
        return false;
    }

    if (xTaskCreate(audioTask, "receiver-audio", 4096, nullptr, 1,
                    &audioTaskHandle) != pdPASS) {
        Serial.println("ERROR: audio task creation failed; receiver continues without audio");
        uninstallAudio();
        return false;
    }
    Serial.printf("I2S configured: BCLK=IO%u LRC=IO%u DIN=IO%u, 16000 Hz stereo 16-bit\n",
                  AUDIO_BCLK_PIN, AUDIO_LRC_PIN, AUDIO_DIN_PIN);
    return true;
}

void playStartupSound() {
    if (audioTaskHandle == nullptr || audioFailed.load()) {
        Serial.println("ERROR: audio unavailable");
        return;
    }
    xTaskNotifyGive(audioTaskHandle);
    Serial.println("AUDIO: chime requested");
}

void receivePacket(const uint8_t* mac, const uint8_t* data, int length) {
    if (length != sizeof(CounterPacket)) {
        return;
    }

    CounterPacket packet;
    memcpy(&packet, data, sizeof(packet));
    if (packet.magic != PACKET_MAGIC ||
        packet.version != PACKET_VERSION ||
        (packet.buttons & 0xf0) != 0) {
        return;
    }

    portENTER_CRITICAL(&packetMux);
    if (packetQueueCount < PACKET_QUEUE_SIZE) {
        ReceivedPacket& entry =
            packetQueue[(packetQueueHead + packetQueueCount) % PACKET_QUEUE_SIZE];
        memcpy(entry.mac, mac, sizeof(entry.mac));
        entry.packet = packet;
        ++packetQueueCount;
    } else {
        ++packetQueueDropped;
    }
    portEXIT_CRITICAL(&packetMux);
}

#if ESP_ARDUINO_VERSION_MAJOR >= 3
void onDataReceived(const esp_now_recv_info_t* info, const uint8_t* data, int length) {
    receivePacket(info->src_addr, data, length);
}
#else
void onDataReceived(const uint8_t* mac, const uint8_t* data, int length) {
    receivePacket(mac, data, length);
}
#endif

bool initializeEspNow() {
    if (!WiFi.mode(WIFI_STA)) {
        return false;
    }
    if (esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
        return false;
    }
    if (esp_wifi_get_mac(WIFI_IF_STA, receiverAddress) != ESP_OK) {
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

void forwardButtons(uint8_t buttons) {
    forwardedButtons = buttons;
    const uint8_t value = 0x80 | buttons;
    if (Serial2.write(value) != 1) {
        Serial.printf("ERROR: Tang UART write failed, byte=0x%02X\n", value);
        return;
    }
    Serial.printf("TANG TX byte=0x%02X buttons=0x%02X (queued, no acknowledgement)\n",
                  value, buttons);
}

void printController(int slot) {
    const uint8_t* mac = arbiter.mac(slot);
    if (mac == nullptr) {
        Serial.print("none");
        return;
    }
    Serial.printf("P%d %02X:%02X:%02X:%02X:%02X:%02X", slot + 1,
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

bool isGameSession(GameAudioMode mode) {
    return mode == GameAudioMode::Flying || mode == GameAudioMode::Landed ||
           mode == GameAudioMode::Crashed;
}

void readTangSerial() {
    static uint8_t lastAudioFrame = 0xff;
    // Bound work so incoming UART traffic cannot starve button forwarding.
    for (size_t i = 0; i < 64 && Serial2.available() > 0; ++i) {
        const int value = Serial2.read();
        if (value >= 0) {
            const uint8_t byte = static_cast<uint8_t>(value);
            if (GameAudioLink::isFrame(byte)) {
                const uint32_t receivedAt = millis();
                portENTER_CRITICAL(&audioLinkMux);
                const bool accepted = gameAudioLink.accept(byte, receivedAt);
                portEXIT_CRITICAL(&audioLinkMux);
                if (!accepted) {
                    Serial.printf("ERROR: invalid game audio frame 0x%02X\n", byte);
                } else if (byte != lastAudioFrame) {
                    const GameAudioState decoded = GameAudioLink::decode(byte & 7u);
                    Serial.printf("AUDIO GAME scene=%u mode=%s thrust=%u\n", byte & 7u,
                                  GameAudioLink::modeName(decoded.mode),
                                  decoded.thrust ? 1u : 0u);
                    lastAudioFrame = byte;
                }
            } else if (GameAudioLink::isSettingsFrame(byte)) {
                const uint8_t music = GameAudioLink::musicVolume(byte);
                const uint8_t effects = GameAudioLink::effectsVolume(byte);
                musicVolume.store(music);
                effectsVolume.store(effects);
                Serial.printf("AUDIO SETTINGS music=%u effects=%u\n", music, effects);
            } else if ((byte & 0xf0u) == 0x80u) {
                Serial.printf("TANG RX byte=0x%02X\n", byte);
            } else {
                Serial.printf("ERROR: unexpected Tang UART byte 0x%02X\n", byte);
            }
        }
    }
}

void sendRandomStatus() {
    StatusPacket packet{
        STATUS_MAGIC,
        PACKET_VERSION,
        static_cast<uint8_t>(Direction::Stop),
        0,
        statusSequence++,
    };

    if (random(5) != 0) {
        packet.direction = static_cast<uint8_t>(random(
            static_cast<uint8_t>(Direction::Down),
            static_cast<uint8_t>(Direction::Up) + 1));
        packet.speed = static_cast<uint8_t>(random(1, 4));
    }

    const esp_err_t result = esp_now_send(
        broadcastAddress,
        reinterpret_cast<const uint8_t*>(&packet),
        sizeof(packet));
    if (result != ESP_OK) {
        Serial.printf("ERROR: status send returned %d\n", result);
        return;
    }

    static const char* const directionNames[] = {
        "STOP", "DOWN", "LEFT", "RIGHT", "UP",
    };
    Serial.printf("DEMO seq=%lu direction=%s speed=%u\n",
                  static_cast<unsigned long>(packet.sequence),
                  directionNames[packet.direction],
                  packet.speed);
}

void handleCommand(const char* command) {
    if (strcmp(command, "status") == 0) {
        portENTER_CRITICAL(&packetMux);
        const uint32_t dropped = packetQueueDropped;
        portEXIT_CRITICAL(&packetMux);
        Serial.printf("status packets=%lu dropped=%lu seq=%lu counter=%lu buttons=0x%02X "
                      "tang=0x%02X session=%u audio=%s\n",
                      static_cast<unsigned long>(packetCount),
                      static_cast<unsigned long>(dropped),
                      static_cast<unsigned long>(lastSequence),
                      static_cast<unsigned long>(lastCounter),
                      lastButtons, forwardedButtons, arbiter.session() ? 1u : 0u,
                      audioTaskHandle != nullptr && !audioFailed.load() ? "ready" : "off");
        Serial.print("player=");
        printController(arbiter.owner());
        Serial.print(" controllers:");
        for (size_t i = 0; i < ControllerArbiter::MAX_CONTROLLERS; ++i) {
            if (arbiter.mac(static_cast<int>(i)) != nullptr) {
                Serial.print(' ');
                printController(static_cast<int>(i));
            }
        }
        Serial.println();
    } else if (strcmp(command, "sound") == 0) {
        playStartupSound();
    } else if (strcmp(command, "audio-demo") == 0) {
        if (audioTaskHandle == nullptr || audioFailed.load()) {
            Serial.println("ERROR: audio unavailable");
        } else {
            audioDemoRequested.store(true);
            Serial.println("AUDIO: game demo requested");
        }
    } else if (strcmp(command, "help") == 0) {
        Serial.println("Commands: status, sound, audio-demo, help");
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
            if (commandLength > 0) {
                commandBuffer[commandLength] = '\0';
                handleCommand(commandBuffer);
            }
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
            commandLength = 0;
            Serial.println("ERROR: command too long");
        }
    }
}

}  // namespace

void setup() {
    Serial.begin(115200);
    Serial2.begin(115200, SERIAL_8N1, TANG_RX_PIN, TANG_TX_PIN);
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LED_OFF);
    delay(500);

    if (!initializeEspNow()) {
        Serial.println("ERROR: ESP-NOW init failed");
        while (true) {
            delay(1000);
        }
    }

    Serial.printf("RX ready, MAC=%02X:%02X:%02X:%02X:%02X:%02X\n",
                  receiverAddress[0], receiverAddress[1], receiverAddress[2],
                  receiverAddress[3], receiverAddress[4], receiverAddress[5]);
    Serial.println("Listening on ESP-NOW channel 1");
    Serial.printf("Tang UART 115200 8N1: RX=IO%u, TX=IO%u; button byte=0x80|mask\n",
                  TANG_RX_PIN, TANG_TX_PIN);
    forwardButtons(0);
    Serial.println("Commands: status, sound, audio-demo, help");
    randomSeed(esp_random());
    nextStatusAt = millis() + static_cast<uint32_t>(
        random(STATUS_MIN_INTERVAL_MS, STATUS_MAX_INTERVAL_MS + 1));
    if (initializeAudio()) {
        playStartupSound();
    }
}

void loop() {
    readSerialCommands();
    readTangSerial();

    const uint32_t now = millis();
    if (static_cast<int32_t>(now - nextStatusAt) >= 0) {
        sendRandomStatus();
        nextStatusAt = now + static_cast<uint32_t>(
            random(STATUS_MIN_INTERVAL_MS, STATUS_MAX_INTERVAL_MS + 1));
    }

    if (ledOn && static_cast<int32_t>(now - ledOffAt) >= 0) {
        digitalWrite(LED_PIN, LED_OFF);
        ledOn = false;
    }

    GameAudioLink linkSnapshot;
    portENTER_CRITICAL(&audioLinkMux);
    linkSnapshot = gameAudioLink;
    portEXIT_CRITICAL(&audioLinkMux);
    if (arbiter.setSession(isGameSession(linkSnapshot.state(now).mode))) {
        Serial.println("PLAYER released: game returned to the lobby");
    }

    bool forward = false;
    for (;;) {
        ReceivedPacket entry;
        bool havePacket = false;
        portENTER_CRITICAL(&packetMux);
        if (packetQueueCount > 0) {
            entry = packetQueue[packetQueueHead];
            packetQueueHead = (packetQueueHead + 1) % PACKET_QUEUE_SIZE;
            --packetQueueCount;
            havePacket = true;
        }
        portEXIT_CRITICAL(&packetMux);
        if (!havePacket) {
            break;
        }

        const CounterPacket& packet = entry.packet;
        ++packetCount;
        lastSequence = packet.sequence;
        lastCounter = packet.counter;
        lastButtons = packet.buttons;
        digitalWrite(LED_PIN, LED_ON);
        ledOn = true;
        ledOffAt = now + LED_PULSE_MS;

        const int previousOwner = arbiter.owner();
        bool relevant = false;
        const int slot = arbiter.packet(
            entry.mac, remapControllerButtons(packet.buttons), now, relevant);
        Serial.printf("RX %02X:%02X:%02X:%02X:%02X:%02X seq=%lu counter=%lu buttons=0x%02X",
                      entry.mac[0], entry.mac[1], entry.mac[2],
                      entry.mac[3], entry.mac[4], entry.mac[5],
                      static_cast<unsigned long>(packet.sequence),
                      static_cast<unsigned long>(packet.counter),
                      packet.buttons);
        if (slot == ControllerArbiter::NONE) {
            Serial.println(" IGNORED: too many controllers");
            continue;
        }
        Serial.printf(" P%d%s\n", slot + 1, relevant ? "" : " IGNORED: not the player");
        if (arbiter.owner() != previousOwner) {
            Serial.print("PLAYER ");
            printController(arbiter.owner());
            Serial.println(" pressed THRUST");
        }
        forward = forward || relevant;
    }

    const uint8_t buttons = arbiter.output(now);
    if (forward || buttons != forwardedButtons) {
        if (!forward && buttons == 0) {
            Serial.println("WARNING: ESP-NOW button timeout; releasing buttons");
        }
        forwardButtons(buttons);
    }
}

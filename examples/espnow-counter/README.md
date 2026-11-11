# ESP-NOW counter test

This test uses two ESP32-WROOM-32 boards. One broadcasts a counter over
ESP-NOW; the other prints received packets to its USB serial port. No wires
between the ESP32 boards are needed for this first test.

## Upload

1. In Arduino IDE, install/select the Espressif ESP32 board package. The
   receiver sketch supports Arduino-ESP32 core 2.x and 3.x.
2. Connect the first board by USB, open
   `espnow-counter-tx/espnow-counter-tx.ino`, select **ESP32 Dev Module** and
   the first board's serial port, then upload.
3. Connect the second board, open
   `espnow-counter-rx/espnow-counter-rx.ino`, select the second board's serial
   port, then upload.
4. Open Serial Monitor on the transmitter at **115200 baud**, set line ending
   to **Newline**, and type `start`. It will broadcast an increasing counter
   once per second. The onboard LED on GPIO 2 flashes for each transmission.
   Type `stop` to pause the counter (buttons remain active), `reset` to set the counter to
   zero, or `status` to inspect the current state.
5. Open Serial Monitor on the receiver at **115200 baud**. While transmission
   is running, it should print received counter packets and its onboard LED on
   GPIO 2 should flash on each packet.

## Receiver audio (MAX98357A)

The receiver plays a three-note startup chime (C5, E5, G5, about 0.6 s).
Send `sound` in its Serial Monitor at 115200 baud to play it again; `status`
also reports `audio=ready` or `audio=off`. Repeated requests during playback
coalesce into one pending replay. The melody was heard during hardware
bring-up. The new receiver build also synthesizes game music, thrust, landing
and crash effects from state frames sent by a compatible Tang build. The new
builds are installed; the user confirmed music and thrust in the game and
the volume of the effects demo. Landing and crash events during actual play
remain to be checked. A later build plays the music at a menu level on the
main screen, the memorial screens and the autopilot demo, and about 1 dB
quieter during play (`MUSIC_MENU_GAIN` and `MUSIC_GAME_GAIN` in
`game_audio.h`). The user reports the installed 1.4/1.05 levels are still too
quiet while other game sounds are normal. The 1.45/1.3 gain update passed the
audio mixer tests and is now installed in the ESP32 app; the receiver reports
`audio=ready`, but the new level still needs to be auditioned. `sound` is
a command on the ESP32 USB serial port, not on the separate UART connected to
Tang. Send `audio-demo` to play a roughly 6.2-second demonstration of the game
sounds (main-screen music, flight, thrust, landing, resumed flight and crash);
it temporarily overrides the live game state. A host program example
and the game interface are documented in
[the software plan](../../docs/09_SOFTWARE_PLAN.md).

The receiver now also contains an original six-voice, 16-bar space-trance
theme, installed on the ESP32 and auditioned at the previous gain levels; the
user said it remained too quiet. The 1.45/1.3 gain update is now installed and
awaits a new listening check. It replaces
the earlier short two-voice loop; it does not use the attached PPK MIDI.

| MAX98357A | Receiver ESP32 |
|---|---|
| BCLK | GPIO32 |
| LRC / WS | GPIO25 |
| DIN | GPIO22 |
| Vin | VCC / 5V |
| GND | GND |
| GAIN, SD | Leave unconnected |
| Speaker + / - | Connect only to the speaker, **never to GND** |

See the [solder-side photo wiring diagram](../../hardware/esp32-max98357a/esp32-max98357a-back-photo-wiring.png).
Disconnect power before changing wiring. The amplifier uses 5 V power, but
the ESP32 GPIO signals remain 3.3 V. Keep the existing UART pins 16/17 and
LED pin 2 unchanged. Use a speaker with a suitable impedance and power rating;
the amplifier can exceed the rating of a 0.5 W speaker.

Audio uses standard Philips I2S, 16 kHz, signed 16-bit stereo with identical
left/right samples, so the module's default `(L+R)/2` mode works. The chime has
8 ms fades and a peak of 7500 out of 32767 (about 22.9% digital full scale),
set by `StartupChime::PEAK` in `startup_chime.h`; the same limit applies to
the mixed game output. Output loudness depends on
the amplifier and speaker; reduce the peak before uploading if needed.
A separate FreeRTOS task feeds I2S and sends silence when idle; it does
not delay ESP-NOW handling or UART button forwarding. Audio errors are
logged and disable sound without disabling the receiver. An I2S log confirms
digital output only: the module has no speaker-presence or playback feedback.
Brownout resets were observed during startup; check the USB cable and power
connections if they recur rather than disabling the brownout detector.

The shared legacy I2S driver keeps compatibility with Arduino-ESP32 2.x/3.x;
core 3.x emits its expected deprecation warning. No extra audio library or
sound file is required.

### Music file

The theme played by `game_audio.h` (`melody[]`, `roots[]`, `thirds[]`) is also
kept as text in `music/original_theme.song` (format `LLSONG 1`): `bpm`, one
chord per two bars (`D3m`, `Bb2`, ...) and lead lines of 16 eighth-note steps
(`D5`, `F#5`, `.` for a rest). The firmware does not read this file yet; keep
it in sync with the arrays by hand. To open it in a MIDI editor:

```sh
python3 scripts/song_to_midi.py music/original_theme.song music/original_theme.mid
```

The MIDI file has lead, bass, pad and arpeggio tracks, as synthesized by the
ESP32.

```sh
arduino-cli compile --fqbn esp32:esp32:esp32 \
   --output-dir build/espnow-counter-rx examples/espnow-counter/espnow-counter-rx
arduino-cli upload --fqbn esp32:esp32:esp32 --port /dev/cu.RECEIVER_PORT \
   --input-dir build/espnow-counter-rx examples/espnow-counter/espnow-counter-rx
```

## Serial and radio behavior

The sketches use the ordinary serial-terminal format: each packet and command
response is printed on its own line. Keep local echo on and use **CRLF** or
**Newline** line endings.

```sh
python3 -m serial.tools.miniterm --echo --parity N --eol CRLF --exit-char 113 /dev/cu.PORT 115200
```

In miniterm, press `q` to exit the terminal. The exit key is consumed locally
and is not sent to the ESP32.

Both sketches set Wi-Fi channel 1 and do not join an access point. The
transmitter broadcasts without encryption for this bench test. ESP-NOW can
drop packets; gaps in `seq` or `counter` are expected and make losses visible.
The transmitter's `esp_now_send` success only means the local stack accepted
the send, not that the receiver got it.

The sketches target a common ESP32 DevKit onboard LED on GPIO 2. Most such
boards have a single-color LED, not an RGB LED, so the two roles cannot have
different LED colors. If a board's LED is wired active-low, change `LED_ON`
and `LED_OFF` in its sketch.

The transmitter sketch supports a 4x4 WS2812/NeoPixel matrix connected with
DIN to GPIO 23 and common GND. It draws the counter's last decimal digit in
green while transmitting, and a centered blue 2x2 square while stopped. For
the demo, the receiver also broadcasts a random movement status every 1-3
seconds. The transmitter animates two pixels in that direction; speed 1 is
green, speed 2 yellow, speed 3 red, upward movement is always red, and STOP
shows a steady blue horizontal bar. The pixel mapping assumes a common
serpentine row layout; if the display is rotated or mirrored, adjust the
matrix mapping in `renderMatrix()` and `renderStatus()`. The sketch requires
the Adafruit NeoPixel library.

The transmitter reads four buttons switching to GND using the internal pull-ups.
Its raw packet bits 0-3 correspond to GPIO 27, GPIO 32, GPIO 25 and GPIO 4.
The receiver swaps raw bits 1 and 2, so the resulting game controls are LEFT on
GPIO 27, THRUST/START on GPIO 25, RIGHT on GPIO 32 and MENU on GPIO 4.
Connect MENU between GPIO 4 and GND to use the controller's sleep mode.
Each input is debounced for 20 ms. LEFT/THRUST/RIGHT packets carry the complete
raw held mask, including simultaneous presses. MENU is handled locally first:
a short press sends a 100 ms MENU pulse **on release**, while a continuous
2-second hold is consumed by the controller and never sent as MENU to Tang.
For example, `0x03` is GPIO 27+GPIO 32
(LEFT+RIGHT after remapping), `0x07` is all three movement buttons, and `0x00` releases
all buttons (MENU is sent only as the short-press pulse described above).
The transmitter's button names in its serial log describe raw
bits, before the receiver's remapping. Button transmission starts
automatically at boot, independently of the counter's `start`/`stop` commands.
Changes (press and release) are broadcast immediately after debouncing; held
buttons are repeated every 100 ms. Counter packets also carry the current mask.
Each locally queued packet is logged in Serial, for example:

```text
TX seq=12 buttons=0x03 LEFT+THRUST
TX seq=13 buttons=0x03 LEFT+THRUST (hold)
TX seq=14 buttons=0x00 none
```

Broadcast does not require a receiver to be present. `TX` confirms local queue
acceptance, not delivery. Send errors are printed explicitly. See the
[transmitter button wiring diagram](../../hardware/esp32-tx-buttons-wiring.png)
and [assembly instructions](../../docs/04_ASSEMBLY_AND_CONNECTIONS.md).
The receiver swaps bits 1 and 2 of each received mask and forwards the mapped
mask as the existing Tang Nano UART button byte (`0x80 | held_mask`) using UART2
at 115200 8N1: GPIO17 TX to Tang FPGA27
RX, GPIO16 RX from Tang FPGA26 TX, with common GND. It logs `RX` for ESP-NOW
packets, `TANG TX` for locally queued UART bytes (both mapped and raw masks),
and `TANG RX` for incoming
UART bytes (hex). At boot it sends `0x80`; after 250 ms without packets it
releases any held buttons with another `0x80`. It does not synthesize press
events from repeated held masks. The console RTL accepts this separate UART
input and ORs its held mask with USB-UART input before generating edge events.
Each source independently releases its buttons after 250 ms without valid
packets. Tang FPGA26 echoes each valid received control byte; `TANG RX` in
the receiver log confirms the UART round trip, not game action. The same TX
carries game audio state frames (scenes 0-7), logged on changes as
`AUDIO GAME scene=N mode=NAME thrust=0|1`; if no
valid frame arrives for more than 500 ms, music and thrust fade out. Tang also
logs a readable copy (`RX 0x82`) on its USB-UART between health reports.
Movement
telemetry is not implemented.

## Several controllers

The receiver tells controllers apart by their ESP-NOW MAC address (up to four;
logged as `P1`..`P4`). On the main screen, memorials, demo and when Tang
sends no game state, buttons from all controllers are merged, and the most
recent controller to press THRUST becomes the player, so the press that starts
a game claims it. While a game is in progress (flying, landed, crashed or
GAME OVER scenes from Tang) only the player's buttons are forwarded; the others
are logged as `IGNORED: not the player`. When the game returns to the main
screen the player is released. `status` prints the player and all known
controllers. The logic is in `espnow-counter-rx/controller_arbiter.h` and is
covered by `tests/test_controller_arbiter.py`. On hardware, two controllers
(`AC:67:B2:2D:22:F0`, `AC:67:B2:2C:D7:14`) were checked: the one whose THRUST
started the game controlled it and the other was ignored during play.

## Controller sleep

Hold **MENU (GPIO 4)** for **2 seconds**. The 4x4 matrix animates a blue square
shrinking to darkness over 560 ms, and a neutral button packet releases any
game controls. Release **all** buttons to finish entering sleep; holding MENU
does not immediately wake the controller. The ESP32 then stops ESP-NOW/Wi-Fi,
blanks the matrix, turns off its GPIO 2 activity LED and enters real **light
sleep**, suspending the CPU while retaining RAM. Any of the four buttons,
switching its input to GND, wakes it. The matrix plays the reverse animation,
the radio/channel/receive callback are restored, and controls resume only
after all buttons have debounced to released. The wake press (including MENU)
does not reach the game. Radio restore failures are logged and retried once
per second. Counter state and its start/stop setting survive; counter sending
and USB command processing pause during transitions and sleep.

This applies only to the handheld ESP32 transmitter. Tang video, the receiver
and game/audio continue running; sleep does **not** pause the game or save it.
An ESP-NOW release packet can be lost, so the existing receiver/Tang 250 ms
timeout remains the fallback. GPIO low-level light-sleep wake supports these
existing active-low buttons independently; classic ESP32 deep-sleep EXT1
offers ALL_LOW rather than ANY_LOW for this wiring.

There is no switched power rail for the WS2812 matrix, USB bridge or board
power LED: the blank matrix and those peripherals still draw standby current.
Light sleep saves CPU/radio power, not complete battery disconnection. USB
serial is not a configured wake source. Actual current consumption and wake
reliability require a powered-board check; no new wiring beyond MENU is needed.

Build the transmitter and run its host button/state-machine regression tests:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32 \
   --build-path build/espnow-counter-tx-sleep \
   examples/espnow-counter/espnow-counter-tx
TMPDIR="$PWD/build" python3 -m unittest discover -s tests -p 'test_controller_power.py'
```

Do not connect ESP32 TX directly to
the Tang's existing USB-UART TX. Keep both boards powered by their own USB,
without connecting their power rails.

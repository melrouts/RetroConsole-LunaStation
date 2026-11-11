# Аппаратный план

## 1. Цель

Создать стабильную FPGA-платформу, на которой можно запускать разные PicoRV32 игры с SD-карты без пересинтеза при обновлении game firmware.

## 2. Блоки FPGA

```text
Clock/PLL
   |
Reset controller
   |
PicoRV32 -- Memory map -- RAM/PSRAM
   |             |             |
   |             +-- SD SPI -- SD card
   |             +-- Input -- 4 buttons
   |             +-- AUDIO_LINK -- UART -- ESP32 -- I²S -- MAX98357A
   |             +-- Video state
   |
HDMI timing --> streaming compositor --> HDMI output
```

## 3. Аппаратные подзадачи

### 3.1 Плата и ограничения

- На фотографиях платы в `hardware/board-photos/` видна маркировка `3674`
  на обратной стороне; использовать schematic `3674`.
- Сверить официальный schematic и constraints именно этого варианта.
- Выписать oscillator frequency.
- Проверить HDMI interface и required PLL clocks.
- SD/TF connector подтвержден схемой 3674; его сигналы отсутствуют в текущем
  PicoTiny constraint file и требуют отдельных assignments.
- Проверить доступную PSRAM.
- Проверить свободные GPIO и onboard functions.
- Подготовить constraints только после проверки.

Официальные источники:

- [Sipeed schematic directory](https://dl.sipeed.com/TANG/Nano%209K/2_Schematic)
   содержит `Tang_Nano_9k_3672_Schematic.pdf` и более новый
   `Tang_nano_9K_3674_schematics.pdf`; board variant нужно определить по
   маркировке платы.
- [Sipeed TangNano-9K-example](https://github.com/sipeed/TangNano-9K-example)
   содержит официальный PicoTiny example и его
   [picotiny.cst](https://raw.githubusercontent.com/sipeed/TangNano-9K-example/main/picotiny/project/picotiny.cst).

В официальных схемах
[3672](https://dl.sipeed.com/TANG/Nano%209K/2_Schematic/Tang_Nano_9k_3672_Schematic.pdf)
и [3674](https://dl.sipeed.com/TANG/Nano%209K/2_Schematic/Tang_nano_9K_3674_schematics.pdf)
подтверждены oscillator 27 MHz на package pin 52, HDMI TMDS пары 71/70,
73/72, 75/74 и clock 69/68, а также TF signals `SCLK` — 36, `MOSI` — 37,
`CS` — 38, `MISO` — 39. Это package pin numbers, не номера отверстий разъема.
Официальный PicoTiny `.cst` подтверждает HDMI и reference clock assignments,
но его reset assignment 4 не следует переносить: схема 3674 маркирует S1/reset
как pin 3 и S2/JTAG select как pin 4.

На фотографиях также виден разъем microSD. Подключенная плата определяется
через JTAG как `GW1N(R)-9C`; JTAG ID не подтверждает полную маркировку
компонента или содержание flash.

По официальной [спецификации Sipeed](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
плата имеет 64 Mbit embedded PSRAM и 27 MHz oscillator. Пины `10, 11, 13,
14, 15, 16` заняты onboard LEDs. Банки GPIO имеют разные VCCO (включая
1.8 V); для внешних кнопок или модулей напряжение проверять по банку каждого
package pin, не предполагать 3.3 V по маркировке платы.

Подтвержденный для платы проекта baseline из официального PicoTiny constraint
file (`GW1NR-LV9QN88PC6/I5`, `GW1NR-9C`, созданный для example 2022 года):

```text
reference clock / sys_clk       52   (27 MHz согласно Sipeed wiki)
resetn / sys_rst_n                4   (board reset/S1 path)
HDMI TMDS data 0                71,70
HDMI TMDS data 1                73,72
HDMI TMDS data 2                75,74
HDMI TMDS clock                 69,68
SPI flash: clk/csb/mosi/miso    59/60/61/62
UART: ser_tx/ser_rx             17/18
GPIO[6]                           3
GPIO[0..5]                    10/11/13/14/15/16 (used by LED example)
```

HDMI и clock assignments baseline совпадают со схемой 3674; остальные
assignments переносить только после проверки функции, направления и VCCO
каждого сигнала. Пины 10, 11, 13, 14, 15 и 16 заняты onboard LEDs. Pin 4
используется схемой как JTAG select/S2, pin 3 связан с S1/reset; ни один из
них пока не назначать игровому input.

### 3.2 Clock/reset

- Создать PLL для system clock и pixel clock.
- Разделить system и pixel domains при необходимости.
- `rtl/reset_sync.sv` реализует asynchronous assert и двухтактный synchronized
  reset release; RTL simulation подтверждает reset sequence.
- Реализовать reset timeout/error indicator.
- Проверить clock-domain crossing для MMIO и frame snapshot.

### 3.3 PicoRV32

- `rtl/picorv32_wrapper.sv` использует стандартный PicoRV32 с native memory
  interface; `rtl/memory_map.sv` реализует instruction/data RAM и базовые MMIO.
- Добавить multiplier только после измерения потребности.
- Добавить hardware version register.
- Добавить firmware status register.

Bring-up top `rtl/tangnano9k_smoke.sv` использует reference clock 27 MHz
напрямую, power-on counter и синхронизированный reset. PLL и timeout FSM еще
не реализованы. Назначены только clock 52 и UART TX 17; HDMI, SD, LEDs и внешние
кнопки этим top не подключены. Debounce пока проверяется отдельно.

Отдельный `rtl/tangnano9k_video.sv` добавляет PLL 27/3*14 = 126 MHz,
hard CLKDIV /5 = 25.2 MHz и OSER10 + ELVDS_OBUF для TMDS. CPU остается
на 27 MHz и не зависит от pixel clock. Pixel reset отпускается через
двухтактный reset synchronizer только при PLL lock. Потеря lock сбрасывает
pixel domain и serializer; отсутствие кадров 100 ms дает UART `FAIL`.
Фиксация отдельного PLL_TIMEOUT за 10 ms пока не реализована.

`hardware/platform_config.vh` — источник RAM/clock configuration для RTL и
Makefile/linker: RAM 8192 bytes, stack 1024 bytes, PSRAM 0. Physical PSRAM на
плате не означает готовность ее контроллера; feature bit 8 остается равным 0.

### 3.4 HDMI

- Реализовать standard 640x480@60 Hz timing.
- Проверить active area, blanking, sync polarity и pixel clock.
- Вывести test color bars.
- Добавить frame counter.
- Добавить vertical blank event.
- Применить streaming compositor без полного framebuffer.
- Сохранять snapshot игрового состояния на границе кадра.

Baseline font ROM: ASCII 32..127, 96 characters, monospace 8x8 pixels,
one bit per pixel, 8 bytes per character in row-major order, bit 7 leftmost.
Это внутренний compositor resource, не CPU MMIO register; его storage и
инициализация должны быть видны в synthesis report.

HDMI bring-up реализует 800x525 total / 640x480 active при 25.2 MHz
(ровно 60 Hz), negative sync: horizontal 16/96/48, vertical 10/2/33.
Compositor содержит полосы, gradient, border, title и движущийся marker;
позиция marker изменяется только на начале vblank. ASCII ROM 768 bytes
получается из pinned public-domain `third_party/font8x8/font8x8_basic.h`
(dhepper/font8x8, commit `8e279d2d864e79128e96188a6b9526cfa3fbfef9`).
`scripts/font_to_hex.py` меняет LSB-left source на MSB-left hardware format.
В этом build ROM отображается на LUT/mux, не отдельную BSRAM.

### 3.5 Compositor

Порядок слоев:

1. background;
2. stars;
3. terrain fill;
4. terrain outline;
5. pads;
6. approach line;
7. particles;
8. lander;
9. result banner;
10. HUD;
11. pause/confirmation overlay.

Каждый слой должен иметь bounding box или дешевую проверку. Пиксельный поток нельзя останавливать. Если используется pipeline, sync и active-video задерживаются на такое же число тактов.

`COMPOSITOR_PIPELINE_CYCLES` должен быть измерен в RTL simulation и записан в
video interface report. Он не фиксируется предположением до появления RTL.
Тест обязан сравнивать задержанные `hsync`, `vsync` и `active` с RGB output и
проверять, что frame snapshot меняется только на согласованной границе кадра.

Для текущего test-pattern compositor измерено
`COMPOSITOR_PIPELINE_CYCLES = 1`, затем еще 1 cycle TMDS encoder.
В текущей console compositor имеет 3 cycles (terrain/artwork/layout read,
затем синхронный font ROM и фон, затем text overlay/RGB output),
плюс 1 cycle TMDS. `tb_video_game` проверяет согласование
RGB/active/sync как для игры, так и fallback pattern. `video_snapshot`
фиксирует 224-bit bundle и terrain bank только на vblank через request/ack CDC.
Vblank toggle проходит двухтактный CDC в reference domain; FRAME_COUNTER
считается уже там, 32-bit asynchronous bus не пересекает clock boundary.

### 3.6 SD

Реализованы `sd_spi.sv`, SD driver, CRC16 block reads, MBR FAT16/FAT32 reader
и LUNA CRC32 bootloader. Console CST назначает SCK 36, MOSI 37, CS 38,
MISO 39 с pull-up. На плате подтвержден boot диагностического SMOKE с Luna9.
Игровой top до добавления UART updater занимал 5163/8640 LUT4, 1637/6480 DFF,
20/26 BSRAM и 1 PLL. Routed Fmax: system 44.40 MHz при требуемых 27,
pixel 34.97 MHz при требуемых 25.2. Это setup/resource gate, не release
hold/recovery sign-off. Application RAM 8 KiB, прежний boot array 12 KiB, terrain
RAM 2048x10 (две банки по 1024, используются первые 640).

Текущий UART updater добавляет CMD24 с CRC16, readback и A/B slots без
изменения FAT metadata. Boot array увеличен до 16 KiB (13.5 code + 2.5 data) для SD game browser.
Ресурсы: LUT4 6312/8640, DFF 1985/6480, BSRAM 22/26; system Fmax 38.84 MHz,
pixel 34.71 MHz. Реальные записи игры по COM подтверждены на Luna9;
SD/пины/частоты/application RAM не изменились.

`scripts/video_assets.py` детерминированно создает оригинальную индексную
графику: 32 направления ландера 32x32x2 bit и Землю 128x128x4 bit.
`video_art.sv` читает оба ROM синхронно; atlas поворачивает корпус, окно,
опоры и пламя целиком, не отдельную точку носа. Earth palette содержит океан,
материки, облака, тень и атмосферный контур. Звезды распределяются hash-ом
по 32x32 tiles и мерцают по frame counter.
Главный экран имеет крупное название, session BEST SCORE, bob/tilt animation
корабля и пульсацию приглашения. Text layout регистрируется перед font ROM
параллельно с artwork/terrain read. До мемориальных заставок общая задержка
была 2 cycles; теперь font ROM перенесен в BSRAM и добавлен согласованный
третий такт compositor. Это освободило LUT для фотографий и подписей.
Пользователь подтвердил правильный поворот корпуса и новое оформление на HDMI.

- SPI mode initialization.
- Block read.
- FAT16/FAT32 read-only parser.
- Root directory scan.
- Case-insensitive `.bin` filter.
- Asset reads for `AD` and `BEST`.
- CRC and size validation.
- Safe error state if card absent or corrupt.

### 3.7 Buttons

- Two flip-flop synchronizer per input.
- Debounce counter.
- Press/release/held events.
- Active-low/active-high configuration.
- Four logical inputs: `LEFT`, `THRUST`, `RIGHT`, `MENU/BACK`.

Target debounce behavior: после synchronizer raw input должен оставаться
стабильным не менее 20 ms для регистрации press или release. RTL переводит
20 ms в cycles через `SYSTEM_CLK_HZ`; поэтому design не привязан к еще не
подтвержденной частоте oscillator/PLL. `held` отражает debounced level, а
`pressed` и `released` являются one-cycle events.

`rtl/button_debounce.sv` реализует synchronizer, configurable polarity и
параметризуемый debounce; `tests/tb_input_control.sv` проверяет короткий bounce,
20 стабильных samples и one-cycle press/release events.

Физические внешние кнопки пока отсутствуют. Пользователь выбрал временный
UART input: RX pin 18, 115200 8N1, packet `0x80 | held_mask` (low 4 bits).
`uart_rx.sv` синхронизирует RX и проверяет stop bit; `uart_buttons.sv`
формирует press/release/held. Invalid packet/framing error отпускает все
кнопки и ставит transport error, следующий valid packet восстанавливает
transport. Нет valid packet 250 ms — release без ложного удержания.
Пользователь подтвердил START/THRUST/поворот на физической плате через
браузерный мост. Это не замена проверки четырех физических кнопок перед release.

### 3.8 Audio

ESP32-приёмник воспроизводит тестовую мелодию при старте и по команде `sound`.
В новой сборке он также получает состояние игры от Tang и синтезирует фоновую
музыку, двигатель, посадку и аварию. Схема, распиновка и проверка:
`04_ASSEMBLY_AND_CONNECTIONS.md`, раздел Audio.

`startup_chime.h` формирует одинаковые 16-битные PCM-сэмплы для обоих
каналов с частотой 16 кГц. Отдельная задача FreeRTOS передаёт их драйверу
I²S; при отсутствии звука передаются нулевые сэмплы. MAX98357A преобразует
цифровой сигнал и управляет одним динамиком. При ошибке аудиодрайвера
приёмник продолжает работать без звука; готовность видна в `status`.

Игровой звук требует совместимых FPGA bitstream, `LUNAR.BIN` и прошивки
ESP32; они установлены, а пользователь подтвердил музыку и тягу в игре и
прослушал демонстрацию эффектов. Посадку и аварию в реальном полёте ещё
нужно проверить. `AUDIO_LINK` и протокол состояний описаны в
`07_HW_INTERFACE.md`.

## 4. Resource budget

Не использовать framebuffer 800x600. Основной расход должен приходиться на:

- PicoRV32;
- firmware RAM/PSRAM interface;
- font/gfx ROM;
- compositor pipeline;
- SD controller;
- UART-арбитраж и MMIO игрового звука; синтез PCM выполняется на ESP32;
- PLL.

После каждого крупного блока выполнять synthesis и фиксировать LUT, FF, BRAM, PLL и timing slack.

Для smoke bitstream от 2026-11-02 итоговый `build/timing.json` сообщает
2092 LUT4, 665 DFF, 4/26 BSRAM, 32 RAM16SDP4, 316 ALU и 0 PLL.
Post-route Fmax — 55.08 MHz при constraint 27 MHz. Это отчет отдельного
bring-up top без HDMI/SD/PSRAM, а не бюджет готовой игровой платформы и не
release hold sign-off. Raw reports и source hashes сохраняются в `build/`.

Для HDMI bring-up `build/video-timing.json`: 2303 LUT4, 830 DFF,
4/26 BSRAM, 1 PLL, 1 CLKDIV и 3 OSER10 output lanes. Fmax: system 51.14 MHz
при 27 MHz, pixel 47.33 MHz при 25.2 MHz. Serial clock 126 MHz назначен
hard serializer, не является fabric datapath. Три `IOLOGIC_DUMMY` в native
report — placement placeholders для serializer, не самостоятельный ресурс
с нулевой физической емкостью.

До появления resource report нельзя обещать конкретный запас RAM, PSRAM или
compositor capacity. Firmware linker и RTL должны экспортировать фактические
`MAIN_RAM_BYTES`, `PSRAM_BYTES` и максимальный image size; build должен
останавливать сборку при переполнении.

## 5. Аппаратные критерии

- HDMI monitor locks reliably.
- Нет dropped/stalled pixels.
- Button input does not float.
- SD read works after cold boot.
- Speaker does not load GPIO directly.
- FPGA reset leaves outputs safe.
- Constraints contain no guessed pins.

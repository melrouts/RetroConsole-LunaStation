# PicoRV32: план интеграции и разработки

## 1. Назначение

PicoRV32 является CPU для game firmware. Документ описывает конкретную интеграцию в Tang Nano 9K, а не общую теорию RISC-V.

Software можно разрабатывать до готовности FPGA, если сначала зафиксировать memory map, MMIO ABI, формат firmware image и timing contract.

## 2. Роль ядра

PicoRV32 выполняет:

- game state machine;
- fixed-point physics;
- terrain и pad generation;
- collision и scoring;
- menu/browser logic;
- attract/demo logic;
- SD file service calls;
- video state updates и публикацию игрового аудиосостояния.

FPGA hardware выполняет операции, чувствительные к тактированию:

- HDMI timing;
- streaming compositor;
- SD SPI transfer;
- input synchronization;
- frame snapshot.

В новой сборке PicoRV32 публикует аудиосостояние в `AUDIO_LINK`, а FPGA
передаёт его по UART. ESP32-приёмник синтезирует звук и выводит его по I²S
через MAX98357A. Передача состояний проверена, пользователь слышал музыку и
тягу в игре; проверка посадки и аварии в реальном полёте ещё предстоит.

## 3. Базовая конфигурация

Первую версию строить на стандартном PicoRV32 с native memory interface и без ОС, MMU и cache.

Параметры, которые должны быть зафиксированы в RTL:

- `ENABLE_REGS_DUALPORT`;
- `ENABLE_COUNTERS`;
- `ENABLE_COUNTERS64`;
- `ENABLE_MUL`;
- `ENABLE_FAST_MUL`;
- `BARREL_SHIFTER`;
- `TWO_CYCLE_ALU`;
- reset vector;
- IRQ/PCPI policy.

Для fixed-point physics желательно включить multiplier, если synthesis resource report оставляет запас. Если ресурсов недостаточно, заменить дорогие операции на shifts/LUT или software helper и сравнить timing.

Текущий `rtl/picorv32_wrapper.sv` фиксирует dualport registers = 1,
counters/counters64/mul/fast-mul/div/barrel-shifter/two-cycle-ALU/IRQ/PCPI = 0,
compressed ISA = 0 и reset vector = 0. Это RV32I smoke configuration,
проверенная с `firmware/smoke.c`.

## 4. Memory map и capacity contract

Адреса v0.1 определены в `07_HW_INTERFACE.md`. Они provisional до ABI freeze,
но software и mock tests уже используют только эти адреса. После freeze любое
изменение требует новой ABI version.

```text
0x00000000 - 0x0000FFFF  boot/application RAM
0x10000000 - 0x1000FFFF  optional PSRAM window
0x80000000                INPUT_STATE
0x80000004                INPUT_EVENT
0x80000008                AUDIO_CONTROL  (диагностический R/W, без звука)
0x8000000C                AUDIO_PERIOD   (диагностический R/W, без звука)
0x80000010                VIDEO_STATUS
0x80000014                FRAME_COUNTER
0x80000018                VBLANK_EVENT
0x8000001C                HARDWARE_VERSION
0x80000020                ABI_VERSION
0x80000024                SD_STATUS
0x80000028                SD_COMMAND
0x8000002C                SD_DATA
0x80000030                BOOT_STATUS
0x80000070                AUDIO_LINK (расширение console)
```

Это резервирование адресного пространства, не обещание 64 KiB BSRAM.
Два `AUDIO_*` регистра хранят значения, но не подключены к звуковому тракту;
их запись и чтение не являются программным интерфейсом воспроизведения.
Игровой интерфейс — отдельный `AUDIO_LINK`; версия и состояния описаны в
`07_HW_INTERFACE.md`.
Текущий smoke top реализует только `0x00000000..0x00001fff` (8 KiB);
stack занимает последние 1024 bytes. `hardware/platform_config.vh` задает
фактическую RAM capacity; linker получает ее из Makefile и проверяет
непересечение image/BSS со stack.

Сейчас `.data` и код инициализируются из bitstream, `start.S` очищает `.bss`.
Это диагностическая программа, не SD bootloader и не game `.BIN`.

Нельзя исполнять firmware непосредственно с SPI SD. Bootloader читает image блоками и загружает его в RAM/PSRAM.

Размеры `MAIN_RAM_BYTES`, `PSRAM_BYTES` и `MAX_IMAGE_BYTES` должны приходить
из hardware configuration. Нельзя предполагать наличие PSRAM без подтверждения
схемой платы и synthesis. Linker script должен иметь assert на размер image,
stack и game state. `size game.elf` входит в CI/host build check.

Если в `HARDWARE_VERSION` установлен bit 8 (`PSRAM_PRESENT`), firmware может
использовать PSRAM window `0x10000000`; иначе доступ к этому диапазону запрещен.
Значение bit 8 становится частью ABI только после подтверждения реального
контроллера PSRAM.

## 5. Reset и startup

Порядок запуска:

1. FPGA reset.
2. PLL lock, target timeout 10 ms measured from the reference clock.
3. RAM ready, target timeout 5 ms; perform a non-destructive write/readback
	test in the reserved boot area.
4. PicoRV32 reset release.
5. Bootloader проверяет hardware/ABI version.
6. Bootloader проверяет SD image header и CRC, target timeout 1 s per operation.
7. Image size/load address/entry point проверяются до копирования.
8. Image копируется в load address.
9. Управление передается на entry point.
10. Firmware инициализирует MMIO, timer, input и game state.

Timeout values являются target requirements; RTL переводит их в количество
циклов после подтверждения system clock. Неверный image или timeout не должен
вызывать bus hang: bootloader записывает соответствующий `BOOT_STATUS` и
переходит в error screen/status state.

## 6. Firmware ABI

Каждый `.BIN` должен содержать:

- magic;
- image format version;
- required hardware ABI version;
- image size;
- load address;
- entry point;
- flags;
- CRC32;
- payload.

Firmware обязан проверять аппаратную версию до обращения к optional registers. Изменение несовместимого MMIO требует увеличения ABI version.

Для baseline firmware использовать `-march=rv32i -mabi=ilp32` без floating
point. Если включается аппаратный multiplier, его наличие должно быть указано
в hardware feature bits; baseline image не должен требовать `M` instructions.

## 7. MMIO access rules

- Использовать `volatile` для всех MMIO pointers.
- Не кэшировать значения input/status без явного решения.
- Очищать event registers определенным документированным способом.
- Не выполнять длинное SD чтение внутри video-critical section.
- Ожидать ready/valid с timeout.
- Любая операция периферии должна завершаться при отсутствии SD или HDMI.

## 8. Прерывания и таймер

Первая версия может использовать polling, если это упрощает bring-up. Минимальный timer нужен для фиксированного physics timestep.

Рекомендуемый порядок:

1. host tests с виртуальным timer;
2. PicoRV32 polling loop;
3. frame/vblank event;
4. optional timer/IRQ после измерения необходимости.

Game logic не должна зависеть от случайной latency SD или variable wall-clock frame time.

## 9. Software-first разработка

До RTL можно реализовать:

- host golden model;
- fixed-point physics;
- terrain generator;
- collision/scoring tests;
- state machine main/demo/menu/game;
- `.BIN` packer и CRC;
- fake MMIO;
- fake SD directory;
- firmware linker/startup;
- unit tests для `mmio.h` wrappers.

После появления минимального RTL те же tests запускаются в Verilator с настоящим PicoRV32 и RAM model.

## 10. Simulation milestones

### P0: CPU smoke test

- reset;
- instruction fetch;
- RAM write/read;
- pass/fail signature.

Реализован в `tests/tb_smoke_soc.sv` с настоящим upstream PicoRV32 и тем же
`build/smoke.hex`, который используется synthesis. Тест декодирует два UART
сообщения `PASS`, затем инжектирует CPU trap и требует `FAIL`. SRAM-проверка
на плате также получила два `PASS` и завершилась reset к существующей flash.

PicoRV32 загружен без изменений из upstream
`YosysHQ/picorv32`, commit `ef203c2b0a3fb793280f5114941416c425c5b461`;
SHA-256 `picorv32.v`:
`0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622`.
ISC license и copyright сохранены в заголовке vendored файла.

### P1: MMIO test

- write/readback диагностических `AUDIO_*` registers, без проверки звука;
- read input register;
- read hardware/ABI version;
- frame counter progression.

### P2: boot test

- valid header;
- invalid magic;
- invalid size;
- CRC error;
- compatible/incompatible ABI.

### P3: game firmware

- deterministic physics;
- state transitions;
- menu selection;
- demo exit on `THRUST`;
- best score policy.

### P4: integrated platform

- HDMI vblank;
- input events;
- SD service;
- video state snapshot;
- `AUDIO_LINK`, UART состояния и синтез игрового звука на ESP32.

## 11. Deliverables

- `firmware/start.S`;
- `firmware/linker.ld`;
- `firmware/mmio.h`;
- `firmware/boot.c`;
- `rtl/picorv32_wrapper.sv`;
- `rtl/memory_map.sv`;
- Verilator testbench;
- CPU smoke firmware;
- documented ABI version;
- resource/timing report.

## 12. Acceptance criteria

- Firmware runs in host golden model.
- Same firmware image runs in Verilator PicoRV32 model.
- Invalid SD image is rejected without a hang.
- Game firmware can be updated without FPGA resynthesis.
- MMIO accesses match `07_HW_INTERFACE.md`.
- CPU, RAM and MMIO remain within Tang Nano 9K resource/timing budget.
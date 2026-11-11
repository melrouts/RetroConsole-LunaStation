# Синтез и прошивка FPGA

## 1. Prerequisites

- Подтвержденная ревизия Tang Nano 9K.
- Device part должен совпадать с официальным schematic/constraint baseline.
	Для сфотографированной платы `3674` подтверждены маркировка FPGA и JTAG
	family `GW1NR-9C`; официальный PicoTiny example задает
	`GW1NR-LV9QN88PC6/I5`.
- Установлен выбранный synthesis/place-and-route toolchain: native OSS CAD
  Suite Yosys + `nextpnr-himbaechel` + `gowin_pack` (как в Makefile E26).
  Gowin EDA остается альтернативой.
- `openFPGALoader` обнаруживает Tang Nano 9K по onboard USB-JTAG.
- Проверенные `.cst` constraints.
- Стабильный USB кабель и питание.

Gowin IDE/Programmer не обязателен для CLI workflow. Native tools E26 успешно
собрали smoke bitstream этого проекта и загрузили его в SRAM на плате 3674
с JTAG ID `0x100481b` (`GW1N(R)-9C`). Проблемный WASM launcher не используется.

## 2. Synthesis workflow

1. Проверить RTL lint.
2. Проверить simulation.
3. Открыть Gowin project или запустить script.
4. Проверить device family и device part.
5. Проверить constraints.
6. Выполнить synthesis.
7. Выполнить place and route.
8. Проверить timing.
9. Сгенерировать bitstream.
10. Сохранить reports.

CLI workflow должен сохранить промежуточный Gowin netlist и packed `.fs`
bitstream, вместе с использованными Yosys scripts, nextpnr options, `.cst`,
clock constraints и полным build log. Пример команды E26
`make -C Electron26.TangNano9K litex-bitstream` относится к отдельному проекту
и не собирает этот репозиторий.

Для этого проекта запускать из его корня:

```bash
make test
make lint
make bitstream
```

Default `OSS_CAD_SUITE` совпадает с Makefile E26; его можно переопределить.
`hardware/platform_config.vh` задает 27 MHz и 8 KiB RAM; linker резервирует
1024 bytes для stack. `hardware/tangnano9k-smoke.cst` назначает только reference
clock pin 52 и UART TX pin 17. PLL, HDMI, SD и external GPIO в этом top нет.

Артефакты: `build/smoke.elf`, `.bin`, `.hex`, `.json`, `.pnr.json`, `.fs`,
`synthesis.log`, `place-route.log`, `timing.json`, `tool-versions.txt`,
`sources.sha256` и `smoke.fs.sha256`. `scripts/check_timing.py` блокирует
packing при отсутствии clocks, constraint ниже 27 MHz, нечисловом Fmax,
недостаточном Fmax или превышении ресурсов.

## 3. Обязательные reports

- LUT utilization;
- FF utilization;
- BRAM utilization;
- PLL usage;
- maximum clock frequency;
- setup/hold slack;
- unconstrained paths;
- warnings.

Не принимать bitstream с отрицательным timing slack или unconstrained clock paths.

Quality gate также блокирует multi-driven nets, unintended inferred latches,
undriven critical signals и ошибки clock-domain crossing. Unused logic и
оптимизационные предупреждения допускаются только с коротким объяснением в
build log; предупреждение нельзя просто скрыть перенаправлением вывода.

Для каждого release сохранять tool version, command/options, constraints,
source revision, synthesis log, resource/timing reports и SHA-256 bitstream.

Smoke build не является release. В native nextpnr report подтвержден
post-route Fmax, но нет полноценного hold/recovery/removal sign-off. UART —
асинхронный serial output, не внешний synchronous timing interface; других
clock domains в этом top нет. Не трактовать этот отчет как acceptance
HDMI/SD platform.

В логе сохраняются ABC warnings о combinational/carry mapping и промежуточных
internal delay targets; окончательный критерий — post-route clock timing.
Предупреждения `gowin_pack` об отсутствии optional numpy/msgspec/fastcrc
относятся к скорости упаковки. Lint исключает только unused debug nets,
blocking assignments и unnamed generate blocks неизмененного upstream
PicoRV32 через `tests/vendor_lint.vlt`; first-party RTL проверяется с `--Wall`.

## 4. Programming

### Временная загрузка в SRAM через JTAG

`openFPGALoader -b tangnano9k <bitstream.fs>` загружает bitstream во volatile
SRAM FPGA; это не записывает SPI flash. Перезапуск или отключение питания
удаляет эту конфигурацию и возвращает плату к boot-from-flash behavior.

```bash
make load-sram
```

Текущая программа платы при этом прерывается; несохраненные данные в ее RAM
не сохраняются. Smoke top выводит `PASS\r\n` либо `FAIL\r\n` по UART 115200,
примерно раз в секунду. `PASS` означает успешный CPU/RAM/MMIO self-test,
не готовность игры.

Для восстановления текущей flash-конфигурации достаточно перезапустить плату
или использовать `openFPGALoader -b tangnano9k --reset`.

Автоматическая SRAM-проверка с двумя `PASS` и гарантированной попыткой reset
в `finally`:

```bash
python scripts/check_board.py --port /dev/cu.usbserial-11401
```

Использовать Python с установленным `pyserial` (включая существующее окружение
E26); serial device выбрать по текущему обнаружению, не копировать имя вслепую.
Порт должен быть свободен от терминала. JSON report сохраняет hash `.fs`,
количество ответов и успешность JTAG reset; он не доказывает функциональное
состояние старой E26 программы после reload.

Проверка 2026-11-02: получены два `PASS`, JTAG SRAM CRC check успешен, затем
выполнен reset к существующей flash. Отчеты — `build/board-check.log` и
`build/board-check.json`; flash и SD не записывались.

### Постоянная запись SPI flash через UART flash manager

В E26 использовалась двухступенчатая схема без Gowin Programmer: сначала
`openFPGALoader` загружает во SRAM отдельный flash-manager bitstream; затем
`program_hardware_flash.py` общается с ним через USB-UART и передает persistent
bitstream и firmware image в SPI flash. До записи скрипт создавал backup всех
4 MiB flash, дважды считывал его для сравнения и проверял CRC. Журнал E26
зафиксировал успешные erase/write/CRC-check и запуск после JTAG reset.

Пример ниже — команда только для checkout E26 с его менеджером, протоколом и
flash layout; она **не применима** к Lunar Lander:

```bash
cd Electron26.TangNano9K
"$HOME/.local/share/electron26-litex/bin/python" \
  firmware/program_hardware_flash.py \
  --loader openFPGALoader \
  --port "$SERIAL_PORT" \
  --dump-baud 230400 \
  --manager build/litex-flash-manager/gateware/sipeed_tang_nano_9k.fs \
  --reader build/flash-dump.bin \
  --bitstream build/hardware/autoboot/gateware/sipeed_tang_nano_9k.fs \
  --image build/hardware/storage/autoboot.bin \
  --backup "$BACKUP_PATH"
```

Этот E26 workflow не является способом установки Lunar Lander.
Первоначально выполнялась только SRAM загрузка. 2026-11-02 по прямому запросу
пользователя telemetry build записан во **внутреннюю configuration flash**
штатным `openFPGALoader -b tangnano9k --write-flash build/console.fs`.
Внешняя 4 MiB SPI flash не менялась. Полная процедура, границы проверки,
сохраненные файлы восстановления и отличие двух flash — в разделе 10
`10_BUILD_AND_UPDATE.md`. Для обычного временного теста по-прежнему
использовать `--write-sram`, не `-f`.

### HDMI bring-up

```bash
make video-bitstream
python scripts/check_board.py --port /dev/cu.usbserial-11401 \
  --bitstream build/video.fs --report build/video-board-check.json --keep-running
```

Python должен иметь `pyserial`. `--keep-running` оставляет успешно проверенный
тест в SRAM для визуального осмотра монитора; при ошибке пытается вернуть
flash, как и default режим. Сигнал — DVI-compatible TMDS через HDMI connector,
640x480@60 Hz без HDMI audio packets. Полосы, белая рамка, подпись
`LUNA9 HDMI 640X480` и движущийся белый квадрат должны быть видны на мониторе.

На плате получены два `PASS` от этого top: CPU self-test завершился,
PLL locked, vblank heartbeat приходит. Тест оставлен работать в SRAM;
flash не записывалась. Это не доказательство monitor lock, правильности цветов
или отсутствия визуальных артефактов — требуется осмотр изображения.
Rollback без записи flash: `openFPGALoader -b tangnano9k --reset`.

Артефакты имеют prefix `build/video`: `.fs`, `.fs.sha256`,
`-sources.sha256`, `-synthesis.log`, `-place-route.log`, `-timing.json`,
`-board-check.json`. Native CST задает P и N pins отдельно с LVDS25E
(в отличие от paired-pin syntax Gowin IDE). SDC использует post-synthesis
pixel net `core.blue_encoder.clk`; gate требует обе fabric constraints 27 и
25.2 MHz, а SDC также задает 126 MHz serial net. Если Yosys меняет имя
pixel net, отсутствие соответствующего clock target останавливает packing.

SD controller и bootloader реализованы: `make console-bitstream` собирает
`build/console.fs`. Console CST дополнительно назначает SD и UART RX pin 18.
Проверка SRAM без записи flash:

```bash
"$HOME/.local/share/electron26-litex/bin/python" scripts/check_board.py \
  --port /dev/cu.usbserial-11401 --bitstream build/console.fs \
  --report build/console-board-check.json --keep-running
```

До нового игрового renderer диагностический console build
`dd58e79e96c3388ba0887ee9aba54bc7b268219201796cfc7f91238c7e18f10c`
подтвержден на плате: SMOKE действительно загружен из onboard Luna9/GAMES.
Пользователь подтвердил HDMI pattern. Новый game-capable build
`4eeb28ec69e860b3c226697fabfb2bdc91d0588142423b3f4bb8a7b75398d852`
отдельно проверен: `build/lunar-board-check.json` содержит два свежих PASS,
SRAM-only, left_running=true, restored_from_flash=false.
На карте присутствует проверенный LUNAR с payload 6876 bytes; пользователь
подтвердил игровой HDMI-экран, старт, тягу и поворот.
После checker запущен локальный keyboard bridge; flash ни разу не записывалась.

Последнее графическое обновление отдельно SRAM-loaded и проверено:
`build/lunar-graphics-board-check.json`, два свежих PASS,
bitstream `f35a1cc2b13200f622db10b8243809945bfdd04c3e1e6bdb38ad58c0a8442908`,
LUNAR payload 6824 bytes, image hash
`479c27389999bd47e0c751cc8973e24ad7f7ac2b81afb2a3fd2ef30f89aa040b`.
Пользователь подтвердил вращение всего корпуса и новое оформление:
Земля, звёздное поле, title/BEST SCORE и анимированный корабль в меню.
Игра и keyboard bridge оставлены работающими. После power-cycle нужен
повторный SRAM load, так как существующая flash не изменена.

Checker очищает serial buffer до загрузки, после загрузки и после дополнительной
паузы 0.5 s, чтобы старые USB-buffered PASS не принимались за новый запуск.
Подтвержденный report содержит ровно два свежих PASS, а не накопленные строки.
Keyboard bridge должен быть остановлен на время checker: UART порт один.

### Console с UART SD updater

Новый `build/console.fs` включает LUP1 service, A/B storage и boot memory
13.5 KiB code + 2.5 KiB data/stack, при прежних 8 KiB application RAM.
Результат native route: LUT4 6312/8640, DFF 1985/6480, BSRAM 22/26;
Fmax system 38.84 MHz при требуемых 27 MHz, pixel 34.71 MHz при 25.2 MHz.
Timing gate не ослаблялся; это не полный release hold/recovery sign-off.

SRAM-only board check: `build/uart-update-board-check.json`, два свежих PASS,
bitstream SHA-256
`36bdbe63e53933a9ee1d440a73c221ade6b7300032bac8eeee74a1c9e0db0de4`.
После однократного provisioning Luna9 реальные CLI и HTTP uploads успешно
выполнили запись SD, readback/commit и перезапуск с PASS. FPGA flash не
менялась. При power-cycle этот updater нужно снова загрузить в SRAM.
Процедура передачи BIN и rollback — в `10_BUILD_AND_UPDATE.md`.

## 5. Отладка

Проверять по слоям:

1. power/reset;
2. clock;
3. test color;
4. PicoRV32 test firmware;
5. SD test;
6. buttons;
7. тест звука ESP32, затем сквозная проверка нового игрового звука;
8. game renderer;
9. full game.

Не отлаживать SD и сложную игру одновременно с первым HDMI bring-up.
Минимальный CPU/RAM/MMIO, HDMI pattern и SD diagnostic boot подтверждены;
игровая аппаратная приемка и полный release еще не готовы.

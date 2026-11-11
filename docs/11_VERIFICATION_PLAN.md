# План проверки

## 1. Host tests

- JavaScript reference traces.
- Fixed-point physics.
- Terrain interpolation.
- Touchdown limits.
- Score formula.
- Level progression.
- Game state transitions.

Для Q16.8 reference trace сначала квантизировать входы и результаты тем же
правилом округления, что и firmware. При согласованных test vectors целевой
допуск: position/velocity не более 1 LSB на tick, angle не более 1 turn unit,
а score и state transitions должны совпадать точно. Длинные traces дополнительно
проверяют, что накопленная drift не превышает 2 pixels за 600 ticks. Если
порядок операций web reference и firmware различается, сначала фиксируется
отдельный quantized golden trace, а не скрывается расхождение увеличением
допуска.

## 2. Firmware tests

- startup and linker layout;
- MMIO reads/writes;
- fixed timestep;
- button events;
- game browser filtering;
- best score records;
- image header and CRC;
- demo does not update score.

## 3. RTL tests

- reset;
- RAM;
- PicoRV32 bus;
- MMIO decode;
- input synchronizer/debounce;
- SD SPI state machine;
- bootloader validation;
- HDMI timing;
- snapshot handshake;
- запись/чтение диагностических audio registers и `AUDIO_LINK`;
- UART-арбитраж эха кнопок и игровых аудиоснимков.

Для текущего CPU bring-up: `make test` запускает Icarus с настоящим PicoRV32,
RV32I firmware и UART decode, отдельный native-memory/MMIO test и reset/input
test. Проверяются RAM boundary и byte strobes, version reads, INPUT_EVENT
W1C с одновременным приходом event, незнакомые адреса без bus hang, два UART
`PASS` и `FAIL` после CPU trap. Host tests проверяют byte order/padding/overflow
firmware packer и порог 27 MHz timing gate. `make lint` проверяет first-party
RTL с Verilator; `make test-verilator` выполняет CPU/UART testbench в Verilator.

`make bitstream` использует native E26 OSS CAD Suite и пишет отчеты в `build/`.
Это проверка только минимального top, не SD/HDMI/video acceptance.

HDMI bring-up: `make video-bitstream` дополнительно проверяет три полных
кадра 800x525, точные active/porch/sync counts, one-cycle compositor alignment,
black blanking, border pixels и snapshot только на vblank. TMDS test
проверяет все control tokens и 4096 data symbols: обратное декодирование,
transition minimization и running DC balance. Gowin PLL/OSER10 являются hard
primitives, не моделируются этими portable tests; их работоспособность требует
board/monitor acceptance. Native lint использует реальные port declarations
из OSS CAD Suite, не success-shaped behavioral stubs.

Host LUNA image tests проверяют wire layout, CRC vectors, RAM/stack bounds,
alignment, truncation/trailing bytes, ABI/flags и corruption каждого byte.
Deploy tests проверяют readback/backup и отказ от invalid image; packer не
должен перезаписывать raw input, в том числе при совпадении inode на
case-insensitive filesystem. Подготовленный diagnostic image лежит в
`Luna9/GAMES/SMOKE.BIN`; его реальный SD boot дополнительно подтвержден на плате.

`make test-boot` исполняет настоящий boot ROM/PicoRV32 через SPI SDHC model:
валидный image запускается, поврежденный payload дает status 5 без jump.
Native C tests покрывают fragmented FAT16/FAT32 GAMES/files, geometry,
короткие chains, directory cycles, named lookup и общий CRC/header contract.
`make test-game-boot` проверяет SD LUNAR при наличии SMOKE раньше него,
публикацию MAIN/terrain, START, PLAY/thrust/fuel и vblank commits; поврежденный
предпочтительный LUNAR должен дать CRC error, не fallback в SMOKE.

UART updater: `make test` включает native A/B fault injection на каждой
границе записи (ошибка/искажение), сохранность прежнего slot и FAT metadata,
отказ от пересекающихся slots/directories, host CRC/pacing/error/timeout
checks и RTL unlock/FIFO/overflow/reset. `make test-update` исполняет
настоящие boot ROM/PicoRV32, UART и SPI SD model: upload diagnostic image
поверх factory LUNAR, CMD24 с проверкой CRC16, readback/commit, CPU reboot
из нового slot. Отдельный сценарий SD write rejection проверяет ERR и
возврат к прежней игре. Pseudo-terminal bridge test также передает полный
LUNAR через HTTP, проверяет блокировку клавиш/параллельного upload и
обязательные DONE + два свежих PASS.

Game host test исполняет неизмененный `updateLander` из `index.html` в Node.js:
600 ticks, позиция <=0.25 pixel, скорость <=0.1 pixel/s, угол <=0.002 rad,
fuel <=0.01 unit. Это bounded drift test исходной float-модели, не замена
будущему quantized golden contract с 1 LSB/tick. Проверяются точные landing
boundaries, integer scoring, sine interpolation, deterministic terrain,
wrap/ceiling, fuel и остановка физики после результата.

UART input test проверяет held/press/release, framing error, invalid packet,
watchdog и recovery. Snapshot test использует разные частоты CPU/pixel:
frozen pending bundle, отсутствие изменений до vblank, ack/busy и terrain
bank switch, отклонение busy writes. Game renderer test проверяет
трехтактное согласование terrain, RGB и control signals, включая отдельный
синхронный font ROM и text overlay.

Festival renderer дополнительно проверяет точную подпись, полный год 2026
без обрезки, смену всех трех captions и возврат к первому. Прокрутка — один
pixel на vblank в течение 48 frames, между переходами 132 frames покоя.
Проверяется прозрачность центрального сообщения и отсутствие старого HUD
branding. `vvp build/video-art.vvp +capture` создает menu/menu-scroll/
menu-centre/menu-cambridge, flight и demo-message PPM — это RTL previews,
не фотографии HDMI.

Мемориальные заставки: `test_memorial_assets.py` проверяет 2-bit ROM,
детерминированность, размеры и английские цитаты. `test_memorial_flow.py`
исполняет настоящий game loop с native MMIO/frame model: MAIN → Luna →
Apollo → DEMO, W прерывает каждую заставку, best score не меняется.
`tb_video_art` проверяет pause/scroll/смену FAX/Eagle/Armstrong,
а также streaming alignment текста/фото. `+capture` добавляет
`luna9-memorial`, `luna9-scroll`, `luna9-fax`, `apollo11-memorial`,
`apollo11-eagle`, `apollo11-step` PPM previews.

Возврат из GAME_OVER: `test_game_over_timeout.py` исполняет тот же настоящий
game loop с native MMIO/frame model от потери последней капсулы. Без ввода кадр
899 еще GAME_OVER, кадр 900 — MAIN_SCREEN со сброшенной игрой и прежним рекордом.
Нажатие A или D перезапускает отсчет (включая нажатие на кадре 899 и несколько
нажатий подряд), удержание и отпускание кнопки — нет; W начинает игру, B сразу
возвращает в меню.

Проверка HTTP/serial моста на pseudo-terminal, без занятия платы:

```bash
"$HOME/.local/share/electron26-litex/bin/python" tests/check_keyboard_bridge.py
```

Проверяются реальные UART bytes, input range, Origin, stale sequence,
PASS reception и явно видимый disconnect. Аппаратные игровой HDMI и
клавиатурные START/THRUST/поворот подтверждены пользователем после запуска
LUNAR с Luna9. Board report `build/lunar-board-check.json`: два свежих PASS,
bitstream SHA-256 `4eeb28ec69e860b3c226697fabfb2bdc91d0588142423b3f4bb8a7b75398d852`.
Графическое обновление: `tb_video_art` проверяет поворот всего корпуса и
пламени на 90 градусов, отсутствие пламени без тяги, минимум 60 stars в
верхней части кадра, наличие Земли, изменение menu sprite во времени,
streaming alignment текста/графики на нескольких строках. Host tests проверяют
все 32 поворота atlas, centroid окна/пламени и материалы планеты.
`vvp build/video-art.vvp +capture` создает `build/menu.ppm`,
`flight-upright.ppm`, `flight-rotated.ppm` из RTL simulation, не фотографии HDMI.
Последний board report — `build/lunar-graphics-board-check.json`, SHA-256
`f35a1cc2b13200f622db10b8243809945bfdd04c3e1e6bdb38ad58c0a8442908`.
Пользователь подтвердил новое оформление и правильное вращение корпуса.
Physical buttons, полная приёмка игрового звука, browser, BEST.SAV, SD removal/recovery,
10 ms PLL timeout и hold sign-off остаются release acceptance задачами.

Отдельный тест ESP32-приёмника с MAX98357A воспроизводит мелодию при старте
и по USB-Serial `sound`; пользователь подтвердил, что мелодию слышно.
`tests/test_espnow_audio.py` проверяет PCM-сэмплы, частоты, огибающую,
тишину, совпадение каналов и повтор. Это не проверка I²S-проводки и не
приёмка игрового звука. Новые `tests/test_espnow_game_audio.py`,
`tests/test_game_audio_control.py`, `tests/tb_uart_link_tx.sv` и тесты boot
проверяют синтез, состояния, UART и отказ игры без совместимого FPGA.
Для уровней музыки `test_espnow_game_audio.py` проверяет декодер всех восьми
сцен, уровни меню и игры, плавность перехода, затухание и перезапуск мелодии,
двигатель и эффекты, а `test_game_audio_control.py` прогоняет реальный игровой
цикл (главный экран, заставки, демо, игра, пауза) и сверяет публикуемые сцены.
Прослушивание этих уровней на плате ещё предстоит; установка и приём сцен
(`scene=4` на главном экране и заставках, `scene=6/7` в демо) подтверждены
журналом `build/music-levels-end-to-end.log`.
Тесты новой шестиголосной композиции проверяют наличие ведущей ноты, уровни
музыки и микс с двигателем; новая прошивка установлена, но звук на плате ещё
не прослушан.
После установки на платы `build/game-audio-end-to-end.log` подтверждает
передачу состояний полёта, тяги и выхода в меню на ESP32 с `audio=ready`.
Пользователь подтвердил музыку и тягу в игре и подходящую громкость
демонстрации эффектов. Посадка и авария в реальном полёте ещё не проверены.
При старте также наблюдался brownout; питание
требует проверки, если сброс повторяется.

## 4. Video tests

- 640x480 active region;
- 60 Hz frame rate;
- sync polarity;
- test pattern;
- no stalled pixels;
- no tearing;
- 800x600 to 640x480 mapping;
- HUD and sprite priority.

## 5. Synthesis tests

- positive setup/hold slack;
- no unconstrained paths;
- expected PLL lock;
- LUT/FF/BRAM utilization under budget;
- no critical warnings ignored.

## 6. Hardware acceptance

1. Cold boot without SD.
2. Cold boot with valid SD.
3. Invalid `.BIN`.
4. Multiple `.BIN` files.
5. Game selection.
6. Firmware update without FPGA update.
7. HDMI output.
8. Four buttons.
9. Игровой звук: события игры и воспроизведение через согласованный интерфейс.
10. Best score persistence.
11. Intro/ad/demo loop.
12. Exit confirmation.
13. Recovery after power cycle.

Каждый acceptance test должен иметь expected result, actual result, board revision, bitstream hash и firmware image hash.

Для каждой release также сохранять versions compiler/Python/Gowin, source
revision и constraints hash, чтобы результат можно было воспроизвести.

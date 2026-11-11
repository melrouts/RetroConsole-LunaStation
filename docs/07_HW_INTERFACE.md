# Hardware interface и MMIO ABI

## 1. Правила ABI

MMIO addresses и register semantics являются контрактом между FPGA platform и games. Изменение несовместимого register требует увеличения ABI version.

Firmware при старте читает hardware version и ABI version. Несовместимый image не запускается.

## 2. Карта MMIO v0.1 (provisional)

Ниже находится development contract для software-first разработки. Адреса и
семантика должны пройти ABI freeze перед первым release bitstream. До freeze
firmware использует `ABI_VERSION = 0x0001`; после freeze изменение адреса или
семантики требует новой ABI version и нового bitstream.

```text
0x80000000 INPUT_STATE
0x80000004 INPUT_EVENT
0x80000008 AUDIO_CONTROL  (диагностический R/W, без звука)
0x8000000C AUDIO_PERIOD   (диагностический R/W, без звука)
0x80000010 VIDEO_STATUS
0x80000014 FRAME_COUNTER
0x80000018 VBLANK_EVENT
0x8000001C HARDWARE_VERSION
0x80000020 ABI_VERSION
0x80000024 SD_STATUS
0x80000028 SD_COMMAND
0x8000002C SD_DATA
0x80000030 BOOT_STATUS
0x80000070 AUDIO_LINK     (расширение console, версия/состояние звука)
0x80000074 AUDIO_CONFIG   (console, громкость музыки/эффектов)
```

Правила v1:

- все registers имеют ширину 32 bit;
- порядок байт в RAM и MMIO — little-endian;
- reserved bits должны читаться как 0 и записываться как 0;
- неизвестные MMIO offsets должны завершать bus transaction без зависания;
- окончательный размер RAM/PSRAM не кодируется в этой таблице и фиксируется в
	hardware configuration после проверки платы и synthesis.

### Текущий smoke top (не полный ABI)

RAM: 8 KiB, hardware version: `0x00000001`, ABI version: `0x00000001`,
PSRAM feature отсутствует. Реализованы INPUT_STATE, INPUT_EVENT (W1C),
AUDIO_CONTROL, AUDIO_PERIOD и BOOT_STATUS. В board top input levels/events
пока подключены к 0; audio registers можно читать/писать с byte enables,
но аудиовыхода нет. В smoke top VIDEO/FRAME/VBLANK/SD читаются как 0;
это не сигнал успешной работы этих устройств. SD/HDMI boot этим firmware
не выполняется.

Неизвестный MMIO offset внутри `0x80000000..0x800000ff` возвращает 0.
Доступ за пределами RAM или MMIO завершает транзакцию со значением
`0xbad00000` и latch-ит diagnostic `bus_fault`, переводящий UART report в
`FAIL`. Он не alias-ит адрес обратно в RAM. RAM имеет byte write strobes,
INPUT_EVENT сохраняет событие, пришедшее одновременно с W1C.

`BOOT_STATUS = READY (7)` в smoke firmware означает только успешный CPU/RAM/
MMIO self-test; это не подтверждение SD boot или готовности игры.

В отдельном `tangnano9k_video` top `VIDEO_STATUS` bit 0 отражает synchronized
PLL lock; общая console core также использует busy/error bits ниже.
`FRAME_COUNTER` — read-only uint32, увеличивается
при начале vblank (modulo 2^32); после FPGA reset начинается с 0.
`VBLANK_EVENT` bit 0 latch-ится до W1C low byte; новый event выигрывает
при одновременной очистке. Переполнение счетчика не является ошибкой. В video-only wrapper SD MISO
подтянут логически к 1; для реальной карты используется console wrapper.

### Текущий звуковой тракт и MMIO

`AUDIO_CONTROL` и `AUDIO_PERIOD` в `rtl/memory_map.sv` — 32-битные
диагностические регистры: они сбрасываются в 0 и хранят записанные значения
с учётом byte enables. Их выходы не подключены в `smoke_soc`, который
используется и console core. Биты не задают громкость или частоту, а запись
не создаёт звук и не отправляет команду ESP32. `firmware/smoke.c` проверяет
только запись и чтение. Эти адреса не являются API игрового звука.

Новая console-сборка добавляет отдельный `AUDIO_LINK` по адресу `0x80000070`.
При чтении он возвращает `0x41554401`; smoke top и старый console bitstream
возвращают 0. `LUNAR.BIN` проверяет версию при старте и при несовпадении
останавливается с `BOOT_STATUS=2`. Следовательно, новую игру нельзя оставлять
на SD с постоянно установленным старым FPGA без решения вопроса совместимости.

Запись с активным младшим byte strobe публикует три младших бита как номер
сцены `sss`; допустимы все восемь значений. Остальные биты программам следует
оставлять нулевыми. Игра передаёт полное состояние приблизительно раз в кадр,
включая DEMO:

| `sss` | Константа в `mmio.h`       | Когда игра её публикует                    | Музыка на ESP32             |
|:-----:|----------------------------|--------------------------------------------|-----------------------------|
| 0     | `GAME_AUDIO_IDLE`          | в обычной работе не публикуется            | плавно затихает             |
| 1     | `GAME_AUDIO_FLYING`        | полёт, подтверждение выхода (пауза)        | игровой уровень             |
| 2     | `GAME_AUDIO_LANDED`        | посадка                                    | текущий уровень             |
| 3     | `GAME_AUDIO_CRASHED`       | авария, GAME OVER                          | текущий уровень             |
| 4     | `GAME_AUDIO_ATTRACT`       | главный экран, заставки Луна-9 и Apollo 11 | уровень меню                |
| 5     | `GAME_AUDIO_FLYING_THRUST` | полёт с тягой                              | игровой уровень + двигатель |
| 6     | `GAME_AUDIO_DEMO`          | полёт автопилота в демо                    | уровень меню                |
| 7     | `GAME_AUDIO_DEMO_THRUST`   | полёт автопилота с тягой                   | уровень меню + двигатель    |

При переходе из полёта (сцены 1, 5, 6, 7) в посадку или аварию ESP32
воспроизводит соответствующий эффект. Это снимок состояния, а не
гарантированная очередь отдельных событий.

`AUDIO_CONFIG` — write-only extension: при записи младшего byte strobe младшие
6 bits кодируют громкость музыки `[5:3]` и эффектов `[2:0]`, обе шкалы 0..7.
Значение передается ESP32 кадром `11mmmeee` (старшие два бита `11`, далее
3-bit music и 3-bit effects); значение 7 соответствует прежней полной
громкости. Bootloader повторяет конфигурацию во время меню, ESP32 применяет её
к музыке, двигателю, посадке и аварии. Стартовая мелодия не регулируется.

Музыка звучит на главном экране, на заставках и в демо на уровне меню, а во
время игры примерно на 1 дБ тише. Установленные уровни заданы константами
`MUSIC_MENU_GAIN` (1,45) и `MUSIC_GAME_GAIN` (1,3) от уровня
синтезированной дорожки в
`examples/espnow-counter/espnow-counter-rx/game_audio.h`. Итоговое соотношение
музыки и двигателя зависит от аранжировки и требует проверки на слух. Смена
уровня плавная (около 0,23 с между уровнями меню и игры) и не перезапускает
мелодию. Тишина (сцена 0 или отсутствие кадров свыше 500 мс) затухает за
0,64 с, а следующая сцена с музыкой начинает мелодию заново. Посадка и авария
не меняют уровень музыки.

Новый тракт:

```text
LUNAR.BIN -> AUDIO_LINK -> FPGA UART TX (FPGA26) -> ESP32 GPIO16 RX
    -> синтез ESP32 -> I²S -> MAX98357A -> динамик
```

UART работает на 115200 8N1 и сохраняет эхо кнопок `0x80 | mask`. Аудиобайт
имеет вид `01sss sss`: сцена `sss` дублируется для обнаружения одиночной
ошибки: idle `0x40`, полёт `0x49`, посадка `0x52`, авария `0x5b`, главный
экран и заставки `0x64`, полёт с тягой `0x6d`, демо `0x76`, демо с тягой
`0x7f`. ESP32 отклоняет байты без префикса `01` и несовпадающие копии. Эхо
кнопок имеет приоритет; ожидающий аудиоснимок может заменяться более новым.
При отсутствии корректных снимков свыше 500 мс музыка и двигатель затихают.
Переполнение очереди эха отражается в диагностике консоли.

Формат кадра и RTL не менялись: сцены 0–3 и 5 сохранили прежний смысл, а 4, 6
и 7 раньше были недопустимы. Поэтому прежний `LUNAR.BIN` работает с новой
прошивкой ESP32 (без музыки на главном экране), а новый `LUNAR.BIN` со старой
прошивкой ESP32 помечает сцены 4, 6 и 7 как недопустимые кадры: заставки и демо
остаются беззвучными. Порядок обновления — в `10_BUILD_AND_UPDATE.md`,
раздел 13.

Тестовая мелодия при старте и команда USB-Serial `sound` остаются независимыми
от MMIO. Подключение — `04_ASSEMBLY_AND_CONNECTIONS.md`, программные примеры —
`09_SOFTWARE_PLAN.md`.

### Console extensions development ABI 1

Console подключает SD pins 36/37/38/39, UART RX 18 и TX 17.
`VIDEO_STATUS`: bit 0 PLL lock, bit 1 snapshot busy, bit 2 sticky video error.
`SD_STATUS`: busy/done/overrun в bits 0/1/2. `SD_COMMAND`: GO bit 0,
CS_n bit 1, clear-overrun bit 2, half-period divider bits 15:8 (0 = 1).
`SD_DATA`: TX byte при записи, последний RX byte при чтении.
Команда во время busy не меняет CS и устанавливает overrun.

Boot memory `0x10000..0x13fff`: нижние 13.5 KiB code read-only
(`0x10000..0x135ff`), верхние 2.5 KiB boot data/BSS/stack
(`0x13600..0x13fff`). Application RAM `0..0x1fff` не содержит
предустановленной игры. Ошибочная запись в boot code ставит bus_fault.

UART updater: `0x80000060` — status: RX available bit 0, TX busy bit 1,
sticky RX overflow/framing/TX-overrun error bit 2, service mode bit 3.
`0x80000064` — RX FIFO pop при чтении, TX byte при записи (только когда
TX busy=0). FIFO — 32 bytes. `0x80000068`: write 1 при свободном TX завершает
service mode и сбрасывает CPU на 8 clocks.
В обычном режиме последовательность `LUNAUPD!` на RX включает service mode
и сбрасывает CPU в bootloader. Сам updater не сбрасывается этим CPU reset,
иначе пропало бы состояние протокола. Клавиатурный RX в service mode
удерживается в reset; TX переключается с диагностических PASS на updater.
Протокол и безопасные A/B slots — в `10_BUILD_AND_UPDATE.md`.

Семь shadow words `0x80000040..0x80000058`:

| Offset | Fields |
| --- | --- |
| 0x40 | ship x bits 9:0, orientation bits 14:10, heading high bit 15, y bits 25:16, heading low bits 27:26, altitude hundreds BCD 31:28 |
| 0x44 | enable bit 0, thrust bit 1, speed risk bits 3:2, UI state bits 7:4, speed BCD bits 19:8, altitude units BCD 23:20, fuel percent bits 31:24 |
| 0x48 | fuel BCD bits 15:0, level BCD 23:16, capsules 27:24, altitude tens BCD 31:28 |
| 0x4c | 8 BCD digits: run score during play, session best in MAIN/DEMO |
| 0x50/54/58 | three pad x1 bits 9:0, x2 bits 25:16 |

`0x8000005c`: write bit 0 commits frozen shadow bundle, read bit 0 busy,
bit 1 error. UI states: 0 PLAY, 1 MAIN, 2 DEMO, 3 LANDED, 4 CRASHED,
5 GAME_OVER, 6 EXIT_CONFIRM, 7 LUNA_MEMORIAL, 8 APOLLO_MEMORIAL,
9 CONSOLE_MENU. For state 9 the six non-flags shadow words contain three
8-character game names; flags select the highlighted row/settings page, status,
and two volume values.
Это development ABI, не окончательный freeze.
Orientation 0 — нос вверх, 8 — вправо, 16 — вниз, 24 — влево,
один шаг = 11.25 градуса. Firmware округляет физический angle к ближайшему
из 32 направлений, сама физика сохраняет прежнюю точность turn units.
Корпус, окно, опоры и пламя берутся из одного повернутого sprite.
Прежние nose dx/dy больше не используются; для обновления development
контракта требуется совместная замена FPGA и LUNAR.BIN (ABI еще не frozen).

Телеметрия использует ранее свободные bits того же атомарного snapshot.
Speed — модуль `(vx, vy)` в целых world m/s, округление вниз после перевода
компонент Q8 в целые; показание насыщается на 999. Высота — вертикальный
просвет от опор (`y + 11`) до `game_ground(x)`, не высота над условным нулем
и не кратчайшее расстояние до склона. Отрицательный просвет отображается как 0.
Heading 0..7 — N, NE, E, SE, S, SW, W, NW; в экранных координатах +y вниз.
Почти вертикальное/горизонтальное движение (соотношение компонент более 2:1)
показывается по соответствующей оси. При нулевом показании скорости вместо
стрелки точка; heading не зависит от угла корпуса.
Risk 0 — green, 1 — yellow, 2/3 — red. Firmware сравнивает модули
неокругленных Q8 `vx/vy` с текущими `game_limit_vx/vy(level)`:
red при превышении любого предела, yellow от 75% предела включительно,
иначе green. Это предупреждение о скорости, а не гарантия посадки:
угол корпуса, положение площадки и направление вертикального движения
по-прежнему проверяет физика.
Старый BIN не заполняет telemetry bits, новый BIN требует нового renderer
для этих показаний; основной ABI/адреса не меняются.

`0x81000000 + 4*x`, x 0..639: write-only inactive terrain bank, height 0..479,
full-word stores. Остальная часть 4 KiB terrain page зарезервирована;
неверные индекс/высота/strobes дают video error. Reads возвращают 0.
Во время busy terrain writes и повторный commit запрещены и дают error.
Shadow registers можно менять: pending bundle остается неизменным.
Commit переключает terrain bank только если были terrain writes.
Request/ack toggles пересекают domains через 2FF; pixel snapshot/bank меняются
только на vblank. CPU обязан дождаться ack/busy=0 до следующего commit.

## 3. Frame snapshot

PicoRV32 изменяет game state в рабочей памяти. На vertical blank аппаратная логика копирует или фиксирует согласованный snapshot для compositor. Compositor использует один snapshot до конца кадра.

Минимальный snapshot:

- lander position;
- velocity;
- angle;
- fuel;
- terrain vertices;
- pads;
- particles;
- HUD values;
- overlay flags.

## 4. Input semantics

```text
INPUT_STATE, read-only:
	bit 0 LEFT held
	bit 1 THRUST held
	bit 2 RIGHT held
	bit 3 MENU/BACK held

INPUT_EVENT, pending events:
	bits 0..3   pressed: LEFT, THRUST, RIGHT, MENU/BACK
	bits 4..7   released: LEFT, THRUST, RIGHT, MENU/BACK
```

`INPUT_STATE` содержит debounced levels. `INPUT_EVENT` latch-ится до записи 1 в
соответствующий bit; чтение не очищает event. Software должен очищать event
после обработки. Exact active level is hidden by the input controller.

В console пока нет физических кнопок: тот же logical ABI получает
USB-UART packets `0x80 | held_mask`, 115200 8N1. Host посылает текущее held
каждые 100 ms; FPGA снимает held через 250 ms без valid packet.
Отдельный UART на FPGA27 принимает тот же формат от ESP32; FPGA26 передаёт
эхо. Held обоих UART объединяются через OR до формирования событий; повтор
одинаковой маски не создаёт press, а отпускание одного источника не отменяет удержание
другим. Таймаут и проверка framing действуют независимо для каждого порта.
Invalid packet/stop bit также отпускает held и переводит UART diagnostic
в FAIL до следующего valid packet. Утрата соединения не оставляет тягу включенной.

## 5. Error semantics

SD error, CRC error, invalid image, unsupported ABI и missing asset должны быть доступны firmware через status registers. Bus operations должны завершаться, даже если SD отсутствует.

Минимальные значения `BOOT_STATUS` должны быть стабильными для v1:

```text
0x00000000 RESET/IDLE
0x00000001 PLL_TIMEOUT
0x00000002 RAM_FAIL
0x00000003 SD_INIT_FAIL
0x00000004 IMAGE_INVALID
0x00000005 IMAGE_CRC_FAIL
0x00000006 ABI_MISMATCH
0x00000007 READY
```

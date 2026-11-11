# Сборка и обновление игры

> Публичный репозиторий не содержит локальные резервные копии flash и старые
> двоичные релизы из `hardware/releases/`. Упоминания этих файлов ниже
> описывают историю конкретной платы; для своей платы соберите образы из
> исходников и заранее сохраните собственную резервную копию. игры

## 0. Что работает сейчас

Минимальный CPU/RAM/MMIO smoke build:

```bash
make test test-verilator lint
make bitstream
```

Сборка использует native OSS CAD Suite E26 и создает `build/smoke.fs`,
timing/resource reports, tool versions и SHA-256 manifests. Команды запускаются
из корня проекта. Подробности и результат проверки на плате — в
`05_SYNTHESIS_AND_PROGRAMMING.md`.

**В текущем smoke top firmware включен в initial RAM contents bitstream:**
изменение firmware требует повторного `make bitstream`. Независимое обновление
игры через SD и bootloader ниже — целевой workflow. Host image packer и
проверенное копирование в `Luna9/GAMES` и SD bootloader уже реализованы.

`make video-bitstream` собирает отдельный CPU+HDMI bring-up `build/video.fs`.
Он также включает smoke firmware в initial RAM contents.

## 1. Разделение

FPGA bitstream и game firmware собираются отдельно.

В `tangnano9k_console` защищенный boot ROM сбрасывает CPU на `0x10000`,
а application RAM изначально нулевая. Игра читается с SD; изменение только
game firmware не требует synthesis совместимого FPGA top.

```bash
make images                    # SMOKE.BIN и первый LUNAR.BIN
make test test-boot test-game-boot
make console-bitstream         # build/console.fs, game renderer + SD + UART RX
```

В новой сборке Lunar payload составляет 4966 bytes; `riscv64-elf-size`
показывает 218 bytes BSS с выравниванием, а stack резервирует 1024 bytes
из 8192. Размер зависит от toolchain и исходников: перекрытие проверяет
linker, header/CRC — packer и CPU loader.
Это ранний прототип, не полный release этапов F-I.
Обновленная графика использует генерируемые `build/lander.hex` и
`build/earth.hex`, которые Makefile включает в FPGA build и source manifest.
При изменении sprite/фона нужен новый FPGA bitstream; только score/game
logic по-прежнему обновляется через BIN. Текущий orientation contract требует
совместимых FPGA и BIN, старый нос-маркер более не используется.

## 2. Сборка firmware

```text
source
  -> compiler
  -> game.elf
  -> game.bin
  -> image header + CRC
  -> LUNAR.BIN
```

Проверять:

- target architecture;
- linker map;
- RAM size;
- entry point;
- image size;
- ABI version;
- CRC.

Baseline RISC-V build flags:

```text
-march=rv32i -mabi=ilp32
```

Floating point запрещен. Toolchain version, compiler target и flags сохранять
в build log.

Для текущего тесного game image используются `-Oz -msave-restore`,
`-ffunction-sections -fdata-sections -Wl,--gc-sections`. RV32I save/restore
helpers берутся из штатного libgcc. Общая level-limit curve не размножается
inlining, и ship reset выполняется на месте без промежуточного struct copy.
Аварийный `fail()` помечен `noinline`: иначе компилятор вставляет его тело в
четыре места (+36 bytes). Пределы посадки и начальное состояние сохранены;
1024-byte stack не уменьшен. В текущей сборке payload и BSS занимают 5184 из
7168 bytes до stack; любое расширение должно заново проходить linker guard
и real-CPU boot.

## 3. Формат image

Использовать точный 32-byte header и CRC rules из `08_SD_CARD_FORMAT.md`.
Packer обязан выдавать binary test vectors, которые bootloader принимает в RTL
simulation. Bootloader отклоняет неправильный magic, format/ABI version, размер,
адреса, header CRC или payload CRC.

## 4. SD package

```text
/GAMES/LUNAR.BIN
/GAMES/OTHERGAME.BIN
/GAMES/AD.RLE
/GAMES/BEST.SAV
```

Имена `.bin` отображаются в меню без учета регистра расширения.

Рабочие host-команды:

```bash
make images
make deploy-smoke
make deploy-games
python3 scripts/game_image.py check build/images/SMOKE.BIN
```

`make deploy-smoke` по умолчанию использует mounted volume `/Volumes/Luna9`;
для другой точки монтирования задать `SD_VOLUME`. Для игрового прототипа:

```bash
python3 scripts/game_image.py pack build/lunar.raw build/images/LUNAR.BIN
python3 scripts/deploy_game.py build/images/LUNAR.BIN --volume /Volumes/Luna9
```

`build/lunar.raw` — compiler output, `build/images/LUNAR.BIN` — готовый LUNA
image первого прототипа. Raw payload и упакованный image нельзя хранить под отличающимися
только регистром именами в одном каталоге: macOS обычно case-insensitive.
Deployer валидирует image, сохраняет предыдущий образ в `GAMES/BACKUP`,
копирует через `.TMP` и проверяет readback, не форматируя карту.

## 5. Обновление игры

### По USB-UART, без извлечения карты после начальной подготовки

Новый console bitstream содержит updater и расширенный защищенный boot ROM
(13.5 KiB code + 2.5 KiB data/stack). Старый graphics bitstream не поддерживает
этот протокол. Первая установка требует **одного** переноса SD на PC:

```bash
# Карта подключена к PC; питание платы отключено.
python3 scripts/provision_updates.py --volume /Volumes/Luna9
diskutil eject /Volumes/Luna9
# Вернуть карту в плату, подключить USB/HDMI.
make test test-update console-lint console-bitstream
# Остановить keyboard bridge и выполнить обычный SRAM board check.
```

Provisioning не форматирует карту и не заменяет `LUNAR.BIN`; создает два
8192-byte контейнера `GAMES/UPDATEA.BIN`, `GAMES/UPDATEB.BIN`.
Этот первоначальный board check использовал SRAM и не менял flash. Позднее
отдельно разрешённая постоянная запись описана в разделе 10.

После запуска нового keyboard bridge открыть `http://127.0.0.1:8769`,
выбрать готовый `build/images/LUNAR.BIN` и нажать **Обновить игру**.
На время передачи игра останавливается, кнопки блокируются; страница
показывает передачу, запись/readback и проверку перезапуска. Успех сообщается
только после `DONE` и двух новых UART `PASS`. HDMI во время service mode может
показывать последний кадр; индикатор обновления находится на PC.
Один UART принадлежит только одному процессу: отдельный serial terminal,
checker и CLI uploader должны быть закрыты во время работы моста.

CLI-альтернатива (мост предварительно остановить):

```bash
make images
"$HOME/.local/share/electron26-litex/bin/python" scripts/serial_update.py \
  build/images/LUNAR.BIN --port /dev/cu.usbserial-11401
```

LUP1 transport, 115200 8N1:

1. Host отпускает кнопки (`0x80`), очищает старый RX и посылает `LUNAUPD!`.
2. Bootloader проверяет SD/slots и отвечает `READY LUP1\n`.
3. Host посылает `<4sII>`: `LUP1`, полный размер LUNA файла, CRC32 всего файла.
4. После `SEND\n` идут blocks до 64 bytes: uint16 index, data,
   CRC32(index+data). На каждый block требуется `ACK\n`, без pipelining.
5. После общей CRC — `WRITE\n`, запись неактивного slot с readback,
   `DONE\n`, reset CPU, запуск самой новой валидной игры.

Integer fields little-endian. `ERR slots/header/size/block/crc/generation/
write/sd/read` — явная ошибка, не успех. Receive timeout завершает service
mode и перезапускает прежнюю игру. Автоматического retry/resume нет:
после ошибки повторить весь upload. Успех readback не гарантирует, что новая
игра логически исправна: ошибку приложения можно исправить новым upload;
если образ не выдает PASS, host явно сообщает timeout.

Формат slots и пределы защиты от обрыва питания —
`08_SD_CARD_FORMAT.md`. Запись factory `LUNAR.BIN` через PC больше не меняет
активную игру при наличии валидного update slot. Для обычного rollback
передать прежний BIN через UART: он получит новый generation. Для возврата к
factory выключить плату, подключить карту к PC и удалить оба UPDATEA/B;
повторный provisioning создаст пустые slots, не трогая factory.

Установка на физическую плату выполнена: Luna9 подготовлена без изменения
factory BIN, updater загружен в SRAM, затем две передачи LUNAR (CLI и
HTTP-панель) успешно записали по очереди A/B с readback и новыми PASS после
перезапуска. Отчеты: `build/uart-update-board-check.json`,
`build/uart-update-first.log`, `build/uart-update-http.log`.
FPGA SHA-256:
`36bdbe63e53933a9ee1d440a73c221ade6b7300032bac8eeee74a1c9e0db0de4`.
LUNAR SHA-256 остается
`479c27389999bd47e0c751cc8973e24ad7f7ac2b81afb2a3fd2ef30f89aa040b`.
На момент этой проверки после отключения питания SD slots сохранялись, а
FPGA возвращалась к прежней flash configuration. Более поздняя постоянная
установка описана в разделе 10.

### Ручное копирование factory image

1. Изменить firmware source.
2. Запустить firmware build.
3. Проверить тесты.
4. Упаковать новый image.
5. Проверить CRC и размер.
6. Скопировать файл на SD.
7. Вставить SD и включить плату.
8. После загрузки обновления bootloader возвращается в главное меню; для
   запуска выбранного образа нажать кнопку подтверждения.

FPGA не перепрошивать.

Карту переносить между PC и onboard socket вручную: перед извлечением из PC
безопасно eject, перед извлечением из платы остановить ее/отключить питание.
Deployer отказывается писать в отсутствующий mounted volume и не форматирует
карту. Клавиатурный мост запускать после board check:

```bash
"$HOME/.local/share/electron26-litex/bin/python" scripts/keyboard_bridge.py \
  --port /dev/cu.usbserial-11401
# Затем http://127.0.0.1:8769, только одно управляющее окно.
```

W/Up/Space — старт/тяга; A/Left, D/Right — поворот; B/Escape —
EXIT_CONFIRM, W — выйти, B — продолжить. Мост слушает только loopback,
отклоняет чужой Origin, неверные masks и устаревшие sequence. Потеря фокуса
отпускает кнопки, отсутствие UART packets 250 ms — аппаратный release.
Для моста нужен pyserial; указан уже установленный Python из E26.

## 6. Изменение FPGA

Если меняются RTL, MMIO, clock, HDMI или SD loader:

1. Запустить RTL tests.
2. Запустить synthesis.
3. Проверить timing/resource reports.
4. Получить новый `.fs` bitstream с `.cst` и clock constraints.
5. Сначала временно загрузить и проверить его в SRAM через JTAG:

   ```bash
   make console-bitstream
   openFPGALoader -b tangnano9k --write-sram build/console.fs
   ```

   Это volatile загрузка; после reset/power-cycle FPGA возвращается к
   конфигурации из SPI flash. Для сохранения существующей конфигурации в flash
   этот шаг не требует `--write-flash`/`-f`.

6. Постоянную SPI flash запись разрешать только после появления в этом проекте
   проверенного способа записи с известным layout и backup/restore flow.
   Собственный flash manager/UART protocol обязателен только для такого
   способа записи, а не для обычной JTAG загрузки. Процедура E26 описана как reference в
   `05_SYNTHESIS_AND_PROGRAMMING.md`; ее нельзя применять к Lunar Lander.
7. Проверить compatibility с SD games.

## 7. Rollback

Хранить на компьютере:

- последний рабочий bitstream;
- последний рабочий `.BIN`;
- checksums;
- hardware ABI version;
- build log.

При ошибке нового firmware вернуть предыдущий `.BIN` без изменения FPGA.

Перед программированием нового bitstream сохранить предыдущий bitstream,
constraints и hash. Если новая FPGA-прошивка не стартует, подключить плату по
USB/JTAG и временно загрузить backup bitstream командой
`openFPGALoader -b tangnano9k <backup.fs>`. Для постоянного восстановления SPI
flash использовать только проверенный для layout данной платы workflow;
не запускать запись неизвестного образа или layout.

После временного `make load-sram` reload существующей flash выполняется без
ее записи: `openFPGALoader -b tangnano9k --reset`.

При загрузке console с заполненными A/B slots bootloader сначала проверяет
их CRC: на Luna9 наблюдался стартовый FAIL на первой секунде, затем стабильные
PASS. Для такого cold boot использовать `check_board.py --boot-settle-seconds 2`:
после дополнительных двух секунд startup ожидания RX снова очищается, затем
по-прежнему требуются два свежих PASS, любой FAIL в проверочном окне — ошибка.
Проверочный timeout и timing gate не увеличиваются/не ослабляются.

Festival-оформление загружено в SRAM: `build/festival-board-check.json`,
FPGA SHA-256
`387c960ad50fe69c622893dae02f0a19b6eba4a0c6ccd62dce3b479b391c7319`.
Game BIN и оба SD slots не менялись при этом обновлении renderer.
Ресурсы LUT4 7463/8640, DFF 1998/6480, BSRAM 22/26;
Fmax system 39.95 MHz, pixel 32.96 MHz. Flash не записывалась.

Перед повторным packing console существующий `.fs` автоматически копируется в
`build/bitstream-backup/<sha256>.fs`. Это backup с компьютера, не readback flash.

## 8. Мемориальные заставки демо

`scripts/memorial_assets.py` использует Pillow и генерирует:
`build/memorial.hex` (две фотографии 128x64, 2 bit/pixel, масштаб x4)
и `build/memorial-text.hex` (общий синхронный ROM текста заставок/menu/messages).
Aspect ratio сохраняется, изображения не растягиваются и не обрезаются.
Luna 9 берется из `photos/luna9-capsule.jpg`: это фотография посадочной
капсулы в музее, автор Stolbovsky, лицензия CC BY 4.0. В репозитории
сохранена уменьшенная копия, для ROM она переводится в четыре оттенка.
Источник и условия использования указаны в [photos/README.md](../photos/README.md).
Apollo 11 — NASA image `6900956`: Buzz Aldrin рядом с Eagle, фото Neil Armstrong.
Источник: https://images.nasa.gov/details/6900956 ;
файл https://images-assets.nasa.gov/image/6900956/6900956~small.jpg .
Фото и ответ NASA API с описанием/атрибуцией сохранены в `photos/`.

Новые UI states требуют совместимых FPGA и BIN: сначала SRAM renderer,
затем game BIN через COM. Именно в таком порядке установлено на плату.
Отчеты `build/memorial-board-check.json`, `build/memorial-game-upload.log`.
FPGA SHA-256:
`acb141ca15363dfa16d58197122a81c8c99345889cf3eefcc6d93958307ef7e5`.
Game BIN SHA-256:
`34a73703344ab7a919546934ab66bcdedc883ea64c274814f2c8a6d082cca39b`.
LUT4 6559/8640, DFF 2072/6480, BSRAM 26/26; system Fmax 39.58 MHz,
pixel Fmax 39.56 MHz. BSRAM полностью занят; новые ROM требуют переразмещения,
а не молчаливого переполнения. Native router оставляет предупреждение
о partially-global serial_clk routing, как в festival build; это не полный
HDMI clock/hold sign-off. Сохранены прежние clocks и строгий timing gate.
Flash и factory BIN не изменялись, новый game записан в неактивный SD slot.

## 9. Телеметрия и 15-секундный attract cycle

Установлено совместное обновление FPGA renderer + game BIN:

- HUD занимает y=0..95. Новый ряд показывает SPEED (m/s), ALT (m) и
  восьминаправленную стрелку вектора скорости; при нулевом показании — точку.
  Предупреждение скорости и стрелка: green до 75% текущих пределов посадки,
  yellow от 75% включительно, red при превышении любого предела.
  Высота — просвет опор над рельефом непосредственно под кораблем.
- Земля в полете перенесена на y=112..239, чтобы увеличенный HUD ее не закрывал;
  в меню остается на прежнем месте.
- Весь цикл `Retro Computer Festival 2026` / `Centre for Computer History` /
  `Cambridge` / `Eduard Garanskij  retro@lea.lt` находится внизу меню
  (viewport y=432..479, неподвижная строка y=448). Отдельная подпись убрана.
- MAIN, Luna 9, Apollo 11, DEMO длятся по 900 frames = 15 секунд.
  Ранний outcome demo замораживает физику до окончания интервала.
  W по-прежнему прерывает любой attract screen и запускает игру немедленно.
  Паузы внутри мемориальных подписей остались 4 секунды + вертикальный переход.
- Горизонтальный scroll между целыми экранами не реализован.
  Используется обычное переключение; плавный вертикальный scroll подписей сохранен.

Код использует ранее свободные bits существующего frame snapshot;
точная раскладка в `07_HW_INTERFACE.md`. Новые MMIO-адреса/BSRAM не добавлялись.
Firmware size 6948 bytes + 208 BSS, прежний stack 1024 bytes;
game image с заголовком 6980 bytes. Сохранены точные ограничения физики.

FPGA SHA-256:
`ad29b66cd7408e9a1d954b71a7f6b008a3f8d9e5c2fdda56857276835471d2b4`.
Game BIN SHA-256:
`cccb0d6008f86f44b7f4c21c63658ceb6cf52c5b159bc52f9ea6fd6bbf8d6721`.
LUT4 7331/8640, DFF 2129/6480, BSRAM 26/26.
Fmax system 40.47 MHz, pixel 28.87 MHz. В этом placement прежнее
serial_clk routing warning не появилось; это все еще не полный release
clock/hold sign-off.

`build/telemetry-regressions.log`: host/native и RTL regression;
`build/telemetry-cpu-boot.log`: real PicoRV32 SD boot с новым BIN,
game frames/input и отклонение поврежденного payload CRC.
`build/telemetry-board-check.json`: SRAM load, CRC success, два свежих PASS.
`build/telemetry-game-upload.log`: UART transfer, запись неактивного SD slot,
readback, commit и успешная проверка перезапуска.
Keyboard bridge восстановлен на `http://127.0.0.1:8769/`.
Изображения `build/telemetry-{menu,contact,flight}.png` — RTL render previews,
не фотографии HDMI. Постоянная SPI flash и factory `GAMES/LUNAR.BIN` не менялись.

## 10. Постоянная установка перед отключением питания, 2026-11-02

По отдельному прямому запросу пользователя текущий рабочий telemetry renderer
установлен во **внутреннюю configuration flash GW1NR-9C**, не во внешнюю
SPI flash. На этой плате это разные области хранения:

- `openFPGALoader -b tangnano9k -f ...fs` по умолчанию вызывает Gowin
  internal `programFlash`: стирание/запись configuration flash и reload.
- `--external-flash` выбирает отдельную SPI NOR. На плате прочитан JEDEC
  `0x856016`, loader определил `PUYA P25Q32H`, 32 Mbit (4 MiB).
  Ее начало содержит прежние данные, не текущий Lunar bitstream;
  эта память не стиралась и не записывалась.
- Загрузчик 1.2.0 `--dump-flash` для Gowin использует внешний SPI access,
  даже если не задан `--external-flash`. Это **не** backup внутренней
  configuration flash. Не путать две памяти при восстановлении.

Первоначальная попытка снять external dump была остановлена после 49152 bytes:
boundary-scan bit-by-bit чтение оказалось слишком медленным, а dump не покрывает
целевую внутреннюю память. Сохраненный файл
`hardware/flash-backup/external-spi-before-lunar.partial.bin` — только
незавершенный внешний dump, **не полный backup и не файл восстановления**.
Двойного полного backup прежней configuration flash нет; loader его не умеет.
Это ограничение выяснено и сообщено до записи.

Рабочие исходные файлы сохранены отдельно от build:

```text
hardware/releases/telemetry-2026-11-02/console.fs
hardware/releases/telemetry-2026-11-02/LUNAR.BIN
hardware/releases/telemetry-2026-11-02/SHA256SUMS
```

Это копии проверенной новой версии для повторной установки, а не readback
прежней прошивки. SHA-256 соответствует разделу 9.

Фактически выполнено с остановленным keyboard bridge:

```bash
openFPGALoader -b tangnano9k --write-flash --verify --verbose build/console.fs
openFPGALoader -b tangnano9k --reset --verbose
```

Результат `build/permanent-flash-write.log`: internal erase/write завершены,
`CRC check: Success`, status `Done Final`, `Ready`.
Важно: loader явно выводит `writing verification not supported` для internal
flash. Поэтому `--verify` **не является побайтовым readback** этого пути;
доступна проверка checksum загруженной configuration после reload.
Проверка из flash без загрузки SRAM подтверждена отдельно:
`build/permanent-flash-boot-check.json` (`sram_loaded=false`,
`external_flash_written=false`, два свежих `PASS` после 2.5 s settle).
Игровой BIN уже находится в SD A/B slot; SD в этом шаге не перезаписывалась.
Физический cold power cycle еще должен выполнить пользователь; JTAG reload
проверен, но не подменяет наблюдение после полного снятия питания.

### Обновление UART распиновки, 2026-11-05

По запросу пользователя новый `build/console.fs` записан в ту же внутреннюю
configuration flash. В console constraints UART ESP32 переставлен: RX=FPGA27,
TX=FPGA26. После `openFPGALoader -b tangnano9k --reset --verbose` без SRAM
загрузки Tang выдал многочисленные `PASS` и принятые байты `RX 0x80..0x86`;
обратные UART-эхо ESP32 также проверены до постоянной записи. Сборка,
загруженная в flash, имеет SHA-256
`4e2ee6ca24356161a619e2d1646b2f13b9566c1b761465b433a157530148eb82`.
Повторная команда записи сообщила `CRC check: Success`; `--verify` для
внутреннего пути не поддерживает побайтовое чтение. Внешняя 4 MiB SPI flash
и SD не изменялись. Полный холодный power-cycle не выполнялся.

Файл для возврата к прежнему FPGA —
`hardware/releases/tang-uart-remap-2026-11-05/console.fs`; его SHA-256
сохранен рядом в `SHA256SUMS`. Текущая звуковая версия описана в разделах 12 и 13.

Восстановление **прежней версии**, если потребуется: сначала загрузить по UART
совместимый старый BIN, например `hardware/releases/telemetry-2026-11-02/LUNAR.BIN`.
Новый звуковой BIN не запускается на старом FPGA. Затем:

```bash
# Карта с игрой остается в плате, USB питание подключено.
# Остановить процессы, владеющие UART/JTAG.
openFPGALoader -b tangnano9k --write-sram \
  hardware/releases/tang-uart-remap-2026-11-05/console.fs
# Для повторной постоянной установки именно этой версии, с отдельного разрешения:
openFPGALoader -b tangnano9k --write-flash \
  hardware/releases/tang-uart-remap-2026-11-05/console.fs
```

Не добавлять `--external-flash`, `--bulk-erase` или E26 flash-manager.
Предыдущую неизвестную configuration восстановить из этих файлов нельзя.
Эта версия 2026-11-05 не добавляла GPIO-кнопки, игровой звук или SD-backed
assets. Отдельная тестовая мелодия ESP32 не зависела от этой записи FPGA.
Установленная позднее звуковая сборка описана ниже.

## 11. Возврат в меню после GAME OVER

Это изменение затрагивает только game firmware (`firmware/game.c`): RTL, MMIO и
`platform_config.vh` не менялись, поэтому достаточно нового game BIN, FPGA не
перепрошивается; установка — как в разделе 5.

После GAME OVER (потеряна последняя капсула) игра ждет 900 frames
(15 секунд при 60 Hz) и возвращается в MAIN_SCREEN: игра сброшена к
стартовому состоянию, BEST SCORE сохраняется. Каждое нажатие (фронт)
LEFT/RIGHT (A/D) перезапускает отсчет. Удержание и отпускание кнопок отсчет
не сбрасывают, поэтому залипшая кнопка не блокирует возврат. THRUST (W)
по-прежнему сразу начинает новую игру, MENU/BACK (B) — сразу возвращает в
меню. Остальные состояния и attract-цикл не менялись.

Размер: payload 6932 bytes (было 6948), BSS 208 bytes — итого 7140 из 7168
bytes до зарезервированного stack, запас 28 bytes (было 12). Без `noinline`
у `fail()` та же логика переполнила бы запас на 8 bytes. `LUNAR.BIN` — 6964
bytes (header + payload), `SMOKE.BIN` не менялся.

Game BIN SHA-256:
`eb568ae85593d7312dbb88104a0b1e726e9e621455a6af2a1115bff4cf371602`.
Каталог `hardware/releases/telemetry-2026-11-02/` хранит прежнюю версию
(раздел 9) и не менялся; на SD и плату новый BIN этим шагом не устанавливался.

Проверено: `make test` (35 Python-тестов, включая новый
`tests/test_game_over_timeout.py`, и все RTL simulations), `make test-game-boot`
(real PicoRV32 SD boot нового BIN и отклонение поврежденного CRC),
`make test-update` (UART upload, readback/commit и перезапуск из нового slot).

## 12. Игровой звук

Новая сборка добавляет `AUDIO_LINK`, передачу состояния игры по отдельному UART
и синтез музыки и эффектов на ESP32. По разрешению пользователя bitstream
записан во внутреннюю configuration flash Tang, прошивка записана в app0 ESP32,
а игра — в неактивный SD slot с проверкой readback и запуском. Внешняя SPI
flash и статус flash ESP32 не менялись.

Файлы и SHA-256 сохранены в `hardware/releases/game-audio-v1/`:
`console.fs`, `LUNAR.BIN`, `receiver.bin`, прежний `receiver-previous-app0.bin`
и source manifest. Прежний FPGA — в `hardware/releases/tang-uart-remap-2026-11-05/`.
После JTAG reload без SRAM-загрузки получены два `PASS`; загрузчик сообщает
`CRC check: Success`, но побайтовая верификация внутренней flash не
поддерживается. Физический cold power-cycle после записи ещё не проверен.

`build/game-audio-game-upload.log` содержит SD readback/commit и два новых
`PASS`; `build/game-audio-end-to-end.log` подтверждает переходы игрового звука
полёт/тяга/тишина на приёмнике с `audio=ready`. Пользователь подтвердил на слух
тягу и музыку непосредственно в игре, а также подходящую громкость
демонстрации `audio-demo` с посадкой и аварией. Проверка посадки и аварии
непосредственно в полёте ещё предстоит. При старте ESP32 снова наблюдался
brownout с последующим перезапуском; причину просадки питания нужно устранить.

**Совместимость:** новый `LUNAR.BIN` проверяет `AUDIO_LINK` при старте и
останавливается с `BOOT_STATUS=2` на старом FPGA. Поэтому сначала установить
и проверить совместимый FPGA, затем прошивку ESP32 и только после этого
обновлять BIN. Временная загрузка FPGA в SRAM исчезает при отключении питания:
если на SD оставить новый BIN, а во flash — старый FPGA, игра после
power-cycle не запустится. До записи BIN подготовить постоянную совместимую
конфигурацию или проверенный путь возврата предыдущей игры. Постоянная запись
configuration flash требует отдельного подтверждения и проверенного backup;
процедура и ограничения readback — в разделе 10. Не форматировать SD и не
менять статус flash ESP32 для обычного обновления.

## 13. Уровни музыки: главный экран, заставки, демо и игра

Музыка теперь играет не только в игре. На главном экране, заставках Луна-9 и
Apollo 11 и в демо она звучит на уровне меню, а во время игры примерно на 1 дБ
тише, чтобы оставаться слышной на фоне двигателя и эффектов. Смена уровня
плавная и не перезапускает мелодию. Таблица сцен и описание уровней — в
`07_HW_INTERFACE.md`.

Изменены только игра и прошивка ESP32: `firmware/game.c` и `firmware/mmio.h`
(`AUDIO_LINK` использует все восемь сцен, `GAME_AUDIO_THRUST` заменён сценами 5
и 7) и `examples/espnow-counter/espnow-counter-rx/` (`game_audio_link.h`,
`game_audio.h` и журнал `AUDIO GAME scene=… mode=… thrust=…`). RTL, формат кадра,
`AUDIO_LINK_VERSION` и bitstream FPGA не менялись, перепрошивать FPGA не нужно.

Вместо прежнего короткого двухголосного лупа в `game_audio.h` написана
самостоятельная космическая trance-композиция: 16 тактов при 120 BPM, цикл 32 с,
бас, трёхнотная аккордовая подкладка, пульсирующее арпеджио и отдельная ведущая
партия (шесть голосов).
Используется только общее космическое настроение; MIDI-файл PPK «Resurrection»
не копировался и не включался в проект. Композиция запрограммирована
непосредственно в синтезаторе ESP32; отдельного MIDI-файла для неё нет.
Проверка нового score: `make test` (56 Python-тестов и RTL simulations) прошёл;
`arduino-cli compile` собрал ESP32-прошивку (928031 байт программной памяти,
70% flash; бинарный образ 928176 байт) в
`build/espnow-counter-original-theme/`. Тесты проверяют ведущую ноту F5,
уровни игры/меню и отсутствие клиппинга с двигателем.

После пользовательского отзыва о тихой музыке уровни увеличены с 1,25/0,8 до
1,4/1,05 (примерно +1 дБ на главном экране и +2,4 дБ в игре), без превышения
предела микса в тестах. По отдельному разрешению новая прошивка записана только
в app0 ESP32 и проверена чтением (`esptool verify_flash`, SHA-256 совпал);
загрузчик, таблица разделов, FPGA и `LUNAR.BIN` не менялись. После reset
приёмник ответил `audio=ready`. При запуске зафиксирован brownout, затем
прошивка перезапустилась и ответила на `status`; за 12 секунд наблюдения новых
reset не было. Пользователь позже прослушал музыку на этих уровнях и сообщил,
что она всё ещё тихая, хотя двигатель и эффекты звучат нормально.

Уровни подняты до 1,45 в меню/демо и 1,3 в игре (примерно на 0,3 дБ и 1,9 дБ
выше прежних установленных уровней соответственно). После разрешения
пользователя кандидат прошит только в app0 ESP32 по адресу `0x10000`;
`esptool verify_flash` подтвердил совпадение образа, после перезапуска
приёмник ответил `audio=ready`. FPGA и `LUNAR.BIN` не менялись. Новый образ
сохранён в `hardware/releases/game-audio-original-theme-louder/`, предыдущий
app0 для rollback — рядом как `receiver-previous-app0.bin`. Новые уровни ещё
не прослушаны.

Финальный `receiver.bin` и точный предыдущий app0 лежат в
`hardware/releases/game-audio-original-theme-louder/`; SHA-256 нового
приложения — `2ed3942addb4ae79abb1197636f718f9bf6685be59d0ced04c6122ac9d990e25`.
Rollback: записать `receiver-previous-app0.bin` по адресу `0x10000`.

Проверено на хосте: `make test` (56 Python-тестов и все RTL simulations),
в том числе `tests/test_game_audio_control.py` (соответствие состояний сценам и
сквозной прогон реального игрового цикла: главный экран, заставки, демо, игра,
пауза, выход) и `tests/test_espnow_game_audio.py` (декодер, уровни и плавность
перехода, затухание и перезапуск мелодии, двигатель, эффекты посадки и аварии,
пик микса); `make images` (`LUNAR.BIN`: 5030 байт кода и 218 байт BSS при
бюджете 7168 байт); `arduino-cli compile --fqbn esp32:esp32:esp32` для
приёмника (928031 байт программной памяти, 70% flash; бинарный образ
928176 байт).

**Первоначальная установка игрового аудио.** По разрешению пользователя первая
прошивка приёмника была записана
в app0 ESP32 (`esptool write_flash 0x10000`, как в разделе 12): bootloader и
таблица разделов совпадают с установленными и не менялись, перед записью app0
совпал с `hardware/releases/game-audio-v1/receiver.bin`, хеш записанных данных
подтверждён. Игра загружена UART-загрузчиком (`scripts/serial_update.py`: запись
неактивного slot, readback, перезапуск, `PASS`). FPGA, factory-образ на SD и
внешняя flash не менялись. Журнал приёмника на живой связи с Tang
(`build/music-levels-end-to-end.log`): `AUDIO GAME scene=4 mode=attract` на
главном экране и заставках, `scene=6/7 mode=demo` в 15-секундном демо и затем
снова `scene=4`. Игровые сцены 1 и 5 на плате не проверялись. Образы лежат в
`hardware/releases/game-audio-music-levels/`
(`receiver.bin`, `LUNAR.BIN`, `SHA256SUMS`), сборка приёмника — в
`build/espnow-counter-rx-music-levels/` (прежний `build/espnow-counter-rx/` не
перезаписывался). Для возврата к базовой версии v1: app0 из
`hardware/releases/game-audio-v1/receiver.bin` командой
`esptool write_flash 0x10000` и игра `hardware/releases/game-audio-v1/LUNAR.BIN`
через `scripts/serial_update.py`.

**Порядок обновления.** Сначала прошить ESP32-приёмник (команды сборки и
прошивки — `examples/espnow-counter/README.md`), затем записать новый `LUNAR.BIN`
по разделу 5. Прежний `LUNAR.BIN` работает с новой прошивкой ESP32 (сцены 0–3 и
5 не изменились), но без музыки на главном экране. Новый `LUNAR.BIN` со старой
прошивкой ESP32 помечает сцены 4, 6 и 7 как недопустимые кадры
(`ERROR: invalid game audio frame 0x64`, `0x76`, `0x7f`): главный экран,
заставки и демо молчат. Запись прошивки ESP32 и обновление SD, как и раньше,
выполняются только с подтверждения пользователя.

**Громкость.** Уровни заданы в `game_audio.h` долями `GAIN_ONE`:
`MUSIC_MENU_GAIN` (главный экран, заставки, демо; 1,45) и
`MUSIC_GAME_GAIN` (игра; 1,3).
Общий предел микса по-прежнему `StartupChime::PEAK`; тесты
проверяют, что шестиголосная музыка и двигатель не превышают предел. Фактическое
соотношение громкости нужно проверить на слух после установки. После изменения
констант выполнить
`python3 -m unittest tests.test_espnow_game_audio` (тест требует, чтобы игровой
уровень был ниже уровня меню, но не менее его половины) и перепрошить приёмник.

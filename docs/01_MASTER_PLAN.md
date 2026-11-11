1. Best score.
7. Выход из attract sequence по `THRUST` в game browser.
# Tang Nano 9K Lunar Lander: мастер-план

## 1. Цель

Создать игровую консоль на Tang Nano 9K с PicoRV32, HDMI 640x480@60 Hz,
загрузкой игр с SD-карты, четырьмя кнопками управления и игровым звуком.

Поведение и визуальный стиль первой игры берутся из `index.html`. Логический мир остается 800x600 и равномерно масштабируется в 640x480.

## 2. Архитектура

FPGA bitstream содержит стабильную платформу:

- PicoRV32;
- clock/reset;
- RAM/PSRAM interface;
- HDMI timing и потоковый compositor;
- SD SPI controller и bootloader;
- контроллер кнопок;
- MMIO ABI.

Звуковой тракт находится вне FPGA: игра передаёт своё состояние через MMIO и
UART на ESP32-приёмник, который синтезирует музыку и эффекты и передаёт I²S
на MAX98357A и динамик. Совместимые образы установлены, пользователь
подтвердил музыку и тягу непосредственно в игре и громкость демонстрации.
Браузерная версия `index.html` использует отдельный Web Audio API.

Игры находятся на FAT16/FAT32 SD-карте как отдельные `.bin`-файлы. Выбранный файл загружается в RAM/PSRAM, проверяется и запускается PicoRV32. Обновление игры не требует пересинтеза FPGA, пока сохраняются MMIO ABI и формат firmware image.

## 3. Этапы

### Этап A: подтверждение платы

1. Определить точную ревизию Tang Nano 9K.
2. Получить официальные schematic и pinout.
3. Подтвердить HDMI, SD, oscillator, PSRAM и доступные GPIO.
4. Определить электрические уровни и максимальный ток GPIO.
5. Зафиксировать аппаратный контракт.

Результат: подтвержденные constraints и BOM.

### Этап B: инструменты

1. Установить open-source RTL и RISC-V инструменты.
2. Установить и проверить Gowin CLI flow (`Yosys`, native `nextpnr-himbaechel`,
   `gowin_pack`, `openFPGALoader`); Gowin EDA/Programmer — альтернативный путь.
3. Проверить RISC-V toolchain.
4. Проверить Verilator/Icarus/GTKWave.
5. Запустить скрипт диагностики окружения.

Результат: воспроизводимое development environment.

### Параллельная software-дорожка S0-S3

После этапа B software можно начинать независимо от готовности FPGA:

1. Host golden model и fixed-point physics.
2. Unit tests для terrain, collision, scoring и game states.
3. Mock MMIO, mock timer и mock SD directory.
4. PicoRV32 startup/linker и firmware image packer.
5. Verilator CPU/RAM smoke test после появления минимального RTL.
6. Bootloader tests для header, size, entry point, CRC и ABI version.

Эта дорожка зависит только от документов `06_PICORV32_PLAN.md`, `07_HW_INTERFACE.md` и `08_SD_CARD_FORMAT.md`. Она не требует физической платы. К аппаратной платформе software подключается после завершения этапов C-E.

### Этап C: минимальная FPGA-платформа

1. Clock/reset.
2. PicoRV32 и RAM.
3. MMIO registers.
4. Test firmware.
5. RTL simulation.
6. Первичный synthesis.

Результат: PicoRV32 выполняет простую программу на плате.

Минимальный bring-up этапа C подтвержден: `make bitstream` собирает
`build/smoke.fs`, а SRAM-загрузка на плату 3674 выдала два `PASS` по UART.
Используется прямой reference clock 27 MHz без PLL, 8 KiB RAM и базовый MMIO.
Это не готовая игровая платформа: PLL/timeouts, PSRAM, HDMI и SD остаются
отдельными задачами. Постоянная flash не изменена; после проверки выполнен
JTAG reload существующей flash-конфигурации.

### Этап D: HDMI

1. 640x480@60 Hz timing.
2. Test pattern.
3. Font ROM.
4. Frame counter и vertical blank event.
5. Streaming compositor.
6. Snapshot состояния кадра.

Результат: стабильное изображение без tearing.

Реализован отдельный HDMI bring-up: timing, color/gradient pattern, font ROM,
frame counter/vblank MMIO, one-cycle compositor и vblank snapshot animation.
Native build и board UART подтверждают CPU/PLL/frame heartbeat. Пользователь
подтвердил стабильное изображение и движение квадрата. Дополнительно реализован
игровой compositor с двухтактной задержкой, vblank snapshot handshake и
double-buffered terrain; для него нужен отдельный осмотр игры на HDMI.

### Этап E: SD bootloader

1. SPI initialization.
2. Block read.
3. FAT16/FAT32 read-only.
4. Каталог `.bin` файлов.
5. Header и CRC.
6. Загрузка firmware в RAM/PSRAM.

Результат: запуск тестовой игры с SD без изменения bitstream.

На mounted FAT32 карте `Luna9` создан `/GAMES`. Host LUNA v1 pack/check
и безопасный deploy/readback готовы, `SMOKE.BIN` скопирован как диагностика.
SPI, CRC16 block reads, MBR FAT16/FAT32 parser и CPU bootloader реализованы.
Настоящий PicoRV32 загружает payload в первоначально пустую application RAM,
проверяет CRC и передает управление. На плате подтвержден запуск SMOKE с Luna9.
Boot code защищен и отделен от 8 KiB application RAM. Loader предпочитает
`LUNAR.BIN` как начальный выбор, иначе выбирает первый `.BIN`; игры видны в
интерактивном меню загрузчика. Настройки громкости музыки и эффектов сохраняются
в `GAMES/LUNASET.CFG`, если доступна SD-карта.

### Этап F: оригинальная игра

1. Golden model против JavaScript.
2. Fixed-point physics.
3. Terrain и площадки.
4. Collision и scoring.
5. Renderer и HUD.
6. Игровой звук.

Результат: воспроизводимая игра Lunar Lander.

Первый прототип: `firmware/game_engine.c`, `firmware/game.c`, образ
`build/images/LUNAR.BIN`. Реализованы fixed-point механика, terrain/pads,
collision/scoring, капсулы/уровни и аппаратный HUD/renderer. Host test исполняет
исходный `updateLander` из `index.html` в Node.js и сравнивает 600 ticks;
отдельно проверены точные touchdown boundaries и score. Random terrain
детерминирован xorshift32, не повторяет недетерминированный Math.random.
LUNAR скопирован в Luna9/GAMES и запущен с SD на плате. Пользователь
подтвердил изображение, START, THRUST и поворот через клавиатурную панель.
Музыка и эффекты игрового звука реализованы и установлены. Пользователь
подтвердил музыку и тягу в игре и прослушал демонстрацию эффектов; проверка
посадки и аварии в реальном полёте и полная release-приемка ещё впереди.

### Этап G: главная страница и attract mode

1. Best score.
2. Idle timer 10 секунд.
3. Intro animation.
4. Рекламная картинка с SD.
5. Scripted demo.
6. Циклическое повторение.
7. Выход из demo по `THRUST`.

Промежуточный development flow уже имеет MAIN, idle 10 s, DEMO и PLAY.
Полный INTRO/ADVERTISING, BEST.SAV и переход в browser еще отсутствуют:
временно THRUST сразу начинает LUNAR. Это не приемка этапа G.

### Этап H: меню игр

1. Сканирование FAT directory.
2. Фильтр обычных файлов `.BIN`.
3. Выбор игры и запуск из главного меню приставки.
4. Настройки громкости музыки и эффектов с сохранением на SD.
5. Возврат из главного экрана LUNAR в главное меню приставки кнопкой MENU.

Возврат в меню приставки доступен из главного экрана LUNAR. Внутриигровой
`EXIT_CONFIRM` остается отдельным меню выхода; управление в прототипе идет с
клавиатуры через USB-UART, GPIO-кнопки не назначены.

### Этап I: synthesis и release

1. Synthesis.
2. Timing/resource reports.
3. Programming FPGA.
4. Подготовка SD package.
5. Аппаратные acceptance tests.
6. Release package и rollback instructions.

## 4. Критерии готовности

- Игра запускается на Tang Nano 9K.
- HDMI стабильно работает 640x480@60 Hz.
- Кнопки работают с debounce и hold.
- Игра загружается с SD.
- Замена `.bin` не требует пересинтеза.
- Demo и меню игр работают.
- Best score сохраняется на SD.
- Синтез проходит без unconstrained paths.
- Документированы сборка, прошивка и подключение.

## 5. Основные риски

- Неподтвержденные pin assignments.
- Ограничение BRAM/LUT Tang Nano 9K.
- Недостаток памяти для firmware image.
- Ошибки HDMI clocking.
- Сложность FAT parser.
- Перегрузка динамика усилителем, ошибочное подключение мостового выхода и
  просадка питания звукового тракта.

До этапа HDL необходимо подтвердить схему и ревизию платы.

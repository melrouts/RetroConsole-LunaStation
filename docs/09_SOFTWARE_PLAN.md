# Software и firmware план

## 1. Цель

Перенести механику из `index.html` в независимое PicoRV32 firmware, загружаемое с SD-карты.

## 2. Модули

```text
firmware/
  start.S
  boot.c
  game.c
  physics.c
  game.h
  mmio.h
  attract.c
  menu.c
  sd.c
  save.c
  linker.ld
  Makefile
```

Bootloader также поддерживает LUP1 UART service и preallocated A/B slots.
`firmware/update.c/.h` проверяет mapping/CRC и commit-last запись;
`sd.c` реализует CMD24/readback. FAT metadata меняются при сохранении
`GAMES/LUNASET.CFG` с уровнями музыки и эффектов.
Game image сначала принимается в staging application RAM, пока CPU
выполняет защищенный boot ROM, затем записывается только в неактивный slot.
После commit CPU перезапускается и читает самую новую валидную игру.
Подготовка карты, протокол и rollback — `10_BUILD_AND_UPDATE.md`.

### Звук в программах: текущие возможности

Есть два независимых звуковых тракта:

- `index.html` синтезирует музыку и эффекты через Web Audio API браузера.
  Звук идёт на выбранное аудиоустройство компьютера, а не через интерфейс
  ESP32. Для запуска аудио может потребоваться нажатие Play. Во время игры
  `M` переключает общий звук, `N` — музыку; музыку также переключает кнопка
  MUSIC.
- Новая прошивка ESP32-приёмника синтезирует музыку и эффекты по состоянию,
  полученному от игры через FPGA и UART. Отдельно она воспроизводит трёхнотную
  стартовую мелодию или её повтор по USB-Serial `sound`. Команда `audio-demo`
  демонстрирует игровые звуки без запуска игры. Произвольные ноты, звуковые
  файлы и регулировка громкости через команды не предоставляются. Громкость
  музыки и эффектов задается в меню приставки через `AUDIO_CONFIG`.

Новый `LUNAR.BIN` использует `AUDIO_LINK`; старые `AUDIO_CONTROL` и
`AUDIO_PERIOD` остаются только диагностическими регистрами. Для работы нужны
совместимые FPGA, игра и прошивка ESP32; они установлены, пользователь
подтвердил музыку и тягу в игре и подходящую громкость демонстрации эффектов.
Описание подключения и порядок обновления —
`04_ASSEMBLY_AND_CONNECTIONS.md` и `10_BUILD_AND_UPDATE.md`.

Позже добавлены уровни музыки: на главном экране, заставках Луна-9 и Apollo 11
и в демо музыка играет на уровне меню, а во время игры чуть тише, но остаётся
слышной на фоне двигателя и эффектов. Для этого нужны новая прошивка ESP32 и
новый `LUNAR.BIN`; FPGA не меняется. Схема проверена тестами и установлена на
плату (приём сцен подтверждён журналом приёмника), но на слух ещё не
проверена (`10_BUILD_AND_UPDATE.md`, раздел 13).

В исходниках ESP32 теперь есть самостоятельная 16-тактовая шестиголосная
космическая композиция вместо короткого двухголосного лупа. Она установлена на
ESP32, но ещё не прослушана;
подробности и результаты проверки — в разделе 13 файла
`10_BUILD_AND_UPDATE.md`.

#### Использование из программы PicoRV32

Константы находятся в `firmware/mmio.h`. При старте программа проверяет
`AUDIO_LINK == AUDIO_LINK_VERSION` (`0x41554401`), а при отсутствии
возможности должна сообщить об ошибке; `LUNAR.BIN` устанавливает
`BOOT_STATUS=2` и останавливается. Пример состояний:

```c
#include "mmio.h"

/* Вызывать регулярно, например раз в кадр. */
AUDIO_LINK = GAME_AUDIO_ATTRACT;       /* главный экран, заставки: музыка громче */
AUDIO_LINK = GAME_AUDIO_FLYING;        /* полёт в игре: музыка тише */
AUDIO_LINK = GAME_AUDIO_FLYING_THRUST; /* то же с тягой: добавляется двигатель */
AUDIO_LINK = GAME_AUDIO_DEMO;          /* полёт автопилота: музыка как в меню */
AUDIO_LINK = GAME_AUDIO_DEMO_THRUST;   /* то же с тягой */
/* При переходе из полёта: */
AUDIO_LINK = GAME_AUDIO_LANDED; /* либо GAME_AUDIO_CRASHED */
/* Тишина: музыка плавно затихает, двигатель выключается, эффект отменяется. */
AUDIO_LINK = GAME_AUDIO_IDLE;
```

Это полные снимки состояния, не очередь нот: отправлять их чаще 500 мс с
запасом, иначе приёмник заглушит музыку и двигатель. Промежуточный снимок
может быть заменён более новым. Музыка звучит на главном экране, заставках и в
демо на уровне меню, а в игре немного тише, чтобы оставаться слышной на фоне
двигателя и эффектов. Двигатель звучит во время тяги, а эффекты посадки и
аварии возникают при переходе из полёта. В паузе (подтверждении выхода), при
посадке, аварии и GAME OVER музыка продолжается на текущем уровне. Громкость
задают `MUSIC_MENU_GAIN` и `MUSIC_GAME_GAIN` в `game_audio.h` прошивки ESP32.
Схема кадров, ограничения битов и UART приоритеты — в `07_HW_INTERFACE.md`.

#### Вызов тестовой мелодии с компьютера

Программа на компьютере может открыть **USB-Serial приёмника ESP32** на
115200 baud, 8N1 и отправить ASCII `sound\n`. Команда `status\n` возвращает
строку с `audio=ready` или `audio=off`. Ответ `AUDIO: chime requested`
подтверждает принятие запроса, но не наличие динамика и не фактический звук;
при недоступном аудио выводится `ERROR: audio unavailable`. Несколько
запросов во время мелодии объединяются максимум в один ожидающий повтор.
Команда `audio-demo\n` возвращает `AUDIO: game demo requested` и примерно на
6,2 секунды заменяет игровое аудиосостояние демонстрацией: главный экран,
полёт, тяга, посадка, возобновление полёта и авария; затем управление
возвращается к последнему актуальному состоянию игры. Ответ подтверждает
принятие запроса, а не реальный звук из динамика.

Пример на Python с пакетом `pyserial`. Сохраните его, например, как
`sound_test.py` и передайте имя порта приёмника аргументом:
`python3 sound_test.py /dev/cu.usbserial-02054FF7`. Порт следует уточнить
через `arduino-cli board list` и предварительно закрыть Serial Monitor.
Открытие порта на некоторых платах перезапускает ESP32 и стартовую мелодию.

```python
import sys
import time
import serial

port = serial.Serial()
port.port = sys.argv[1]
port.baudrate = 115200
port.timeout = 0.2
port.write_timeout = 1
port.dtr = False
port.rts = False
port.open()
read_buffer = bytearray()

def send(command):
    if port.write(command) != len(command):
        raise OSError("Неполная запись в Serial")
    port.flush()

def read_line():
    read_buffer.extend(port.read_until(b"\n"))
    if not read_buffer.endswith(b"\n"):
        return ""
    line = read_buffer.decode("utf-8", errors="replace").strip()
    read_buffer.clear()
    return line

try:
    deadline = time.monotonic() + 10
    next_status = 0.0
    while time.monotonic() < deadline:
        now = time.monotonic()
        if now >= next_status:
            send(b"status\n")
            next_status = now + 1
        line = read_line()
        if line.startswith("ERROR:"):
            raise RuntimeError(line)
        if line.startswith("status "):
            if line.endswith("audio=ready"):
                break
            raise RuntimeError(line)
    else:
        raise TimeoutError("Приёмник не ответил на status")

    send(b"sound\n")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        line = read_line()
        if line.startswith("ERROR:"):
            raise RuntimeError(line)
        if line == "AUDIO: chime requested":
            print(line)
            break
    else:
        raise TimeoutError("Приёмник не подтвердил запрос sound")
finally:
    port.close()
```

Формат I²S, подключение и настройка `StartupChime::PEAK` описаны в
`04_ASSEMBLY_AND_CONNECTIONS.md`, раздел Audio.

## 3. Fixed-point модель

Реализованный первый прототип: `game_engine.c/.h` и `game.c`, startup и
freestanding `runtime.c`. Позиции, скорости и fuel — signed Q8, angle —
turn units, sin/cos — 65-entry quarter-wave Q1.15 LUT с interpolation.
Update 60 Hz с remainder accumulation; level ограничен приложением до 99.
MMIO renderer получает округленное направление из 32 значений; это не
меняет физический angle. Session best обновляется только по результатам
пользовательской игры, demo его не меняет. MAIN/DEMO получают best в
VIDEO_SCORE, PLAY/result — текущий score. Best не очищается при старте
следующей попытки, но теряется при перезапуске; SD persistence еще отсутствует.
Случайный terrain использует deterministic xorshift32; не обещается совпадение
случайных ландшафтов с JavaScript Math.random.

`tests/test_game_engine.py` исполняет исходный JS updateLander через Node.js
и сравнивает 600 ticks, safe/unsafe touchdown границы +/-1 и score, ceiling,
wrap и fuel exhaustion. Отдельный quantized per-tick golden contract для
release еще не заморожен.

Рекомендуемые форматы:

- position: signed Q16.8;
- velocity/acceleration: signed Q16.8;
- angle: 16-bit turn units, 65536 = 360 degrees;
- sin/cos: Q1.15 LUT;
- fuel/score/counters: integer;
- fixed timestep: documented 60 Hz update.

Все умножения выполнять с расширенными промежуточными регистрами. Критические сравнения touchdown должны быть протестированы отдельно с округлением и saturation.

## 4. Игровые состояния

```text
BOOT
MAIN_SCREEN
INTRO
ADVERTISING
DEMO
CONSOLE_MENU
EXIT_CONFIRM
GAME_START
PLAYING
LANDED
CRASHED
GAME_OVER
ERROR
```

Переходы v1:

Ниже — целевой полный игровой flow. В development LUNAR сейчас только MAIN, DEMO,
PLAY, LANDED, CRASHED, GAME_OVER, EXIT_CONFIRM, LUNA_MEMORIAL, APOLLO_MEMORIAL.
Idle 900 frames открывает Luna 9 (900 frames), затем Apollo 11 (900 frames),
затем автопилотный DEMO (900 frames). Это 15 секунд на каждое состояние при
60 Hz. При ранней посадке/аварии demo физика останавливается, кадр остается
до завершения 900 frames. THRUST из MAIN/DEMO и обеих мемориальных заставок
немедленно запускает игру уже загруженного образа. Список игр и настройки
громкости находятся в отдельном bootloader console menu. После
посадки/аварии — пауза 96 frames, следующий level/попытка; при нуле капсул —
GAME_OVER. На GAME_OVER 900 frames (15 секунд) без нажатия LEFT/RIGHT
(A/D) возвращают в MAIN_SCREEN: нажатие LEFT или
RIGHT перезапускает отсчет, удержание и отпускание кнопок его не сбрасывают,
THRUST начинает новую игру. MENU возвращает в bootloader только с главного
экрана игры; MENU/BACK во время полета оставляет прежнее меню подтверждения
выхода. INTRO, ADVERTISING, BEST.SAV и PSRAM еще не реализованы.

Мемориальные заставки не обновляют рекорд и не меняют физику полета.
Luna: `FIRST SOFT LANDING / ON THE MOON`, затем
`FIRST FAX FROM THE MOON :)` (шутливая подпись, не название миссии).
Apollo: `FIRST HUMANS ON THE MOON`, `THE EAGLE HAS LANDED`, затем
`ONE SMALL STEP FOR A MAN, / ONE GIANT LEAP FOR MANKIND.`.
Каждая подпись стоит 240 frames (4 s), переход вверх занимает 64 frames
с шагом один pixel за vblank. Заголовок миссии и год неподвижны.

| Current | Event | Next | Action |
| --- | --- | --- | --- |
| BOOT | startup complete | CONSOLE_MENU | Show available `.BIN` games |
| CONSOLE_MENU | `LEFT/RIGHT` | CONSOLE_MENU | Change selected game |
| CONSOLE_MENU | `START` | GAME_START | Load selected image |
| CONSOLE_MENU | `MENU` | AUDIO_SETTINGS | Open music/effects volume settings |
| AUDIO_SETTINGS | `LEFT/RIGHT` | AUDIO_SETTINGS | Adjust focused volume |
| AUDIO_SETTINGS | `START` | AUDIO_SETTINGS | Switch music/effects focus |
| AUDIO_SETTINGS | `MENU` | CONSOLE_MENU | Save settings when possible |
| MAIN_SCREEN | `MENU` | CONSOLE_MENU | Return to launcher |
| MAIN_SCREEN | 10 s without input | INTRO | Start attract sequence |
| INTRO/ADVERTISING/DEMO | `THRUST` | PLAYING | Start loaded game |
| INTRO | sequence complete | ADVERTISING | Show `AD.RLE` or placeholder |
| ADVERTISING | sequence complete | DEMO | Start deterministic demo |
| DEMO | sequence complete | MAIN_SCREEN | Do not save demo score |
| GAME_START | image valid | PLAYING | Initialize game state |
| GAME_START | image/SD error | ERROR | Show error code |
| PLAYING | `MENU/BACK` | EXIT_CONFIRM | Pause simulation and render confirmation |
| EXIT_CONFIRM | `THRUST` | MAIN_SCREEN | Discard current run and return to game menu |
| EXIT_CONFIRM | `MENU/BACK` | PLAYING | Cancel and resume without state loss |
| PLAYING | valid touchdown | LANDED | Freeze physics and show result |
| PLAYING | crash | CRASHED | Freeze physics and show result |
| LANDED/CRASHED | result timeout | GAME_OVER | Commit user score if applicable |
| GAME_OVER | `THRUST` | GAME_START | Restart selected game |
| GAME_OVER | timeout | MAIN_SCREEN | Return to game main screen |
| ERROR | any button | CONSOLE_MENU | Clear transient error and retry launcher |

Attract timings other than the 15-second idle threshold are configuration
constants, not implicit delays in rendering code. Demo input and random seed are
fixed, so two demo runs produce the same physics trace.

## 5. Перенос механики

Из web reference перенести:

- gravity progression;
- fuel progression;
- safe/tight tolerances;
- terrain generation;
- terrain interpolation;
- pad selection;
- thrust vector;
- side wrapping;
- ceiling collision;
- touchdown validation;
- landing score;
- capsule count;
- level progression;
- result messages.

## 6. Главный экран и demo

- Показать title и best score.
- Запустить idle timer на 15 секунд.
- Показать короткую intro animation.
- Загрузить advertisement asset с SD.
- Запустить scripted demo.
- В demo использовать те же renderer и physics.
- Не сохранять demo score.
- На главном экране LUNAR кнопка MENU возвращает в главное меню приставки.
- После окончания demo вернуться на `MAIN_SCREEN`; idle timer может снова
  запустить attract sequence.

The game attract sequence runs inside the selected image. The SD game list is
the separate bootloader console menu.

## 7. Console launcher and game list

- Найти root entry `GAMES`, затем читать его FAT16/FAT32 directory/FAT chain.
- Отбросить directories и файлы без `.bin`.
- Сравнивать extension без учета регистра.
- Ограничить максимальное количество entries.
- Пропускать hidden/system entries и подкаталоги, включая `BACKUP`.
- Отображать имена с scrolling/truncation.
- В консольном меню показывать только regular `.BIN` файлы из `/GAMES`.
- `LEFT/RIGHT` менять выбранную игру, `START` запускать ее.
- `MENU` открывает настройки громкости; `START` переключает музыку/эффекты,
  `LEFT/RIGHT` меняют уровень, повторное `MENU` сохраняет конфигурацию на SD,
  если это возможно.
- Из главного экрана игры `MENU` возвращает в консольный загрузчик; игровое
  меню выхода во время полета остается без изменений.

## 8. Сохранение best score

Использовать точный двухкопийный формат `BEST.SAV` из `08_SD_CARD_FORMAT.md`.
Обновлять сначала неактивную запись, перечитать ее и проверить CRC, затем
считать новую запись активной.

При повреждении обеих записей использовать score 0.

## 9. MMIO правила

- Все registers объявлять через `volatile`.
- Не изменять адреса без bump ABI version.
- Firmware проверяет hardware version.
- Не делать длительные SD операции в video-critical section.
- Передавать renderer только согласованный frame snapshot.

## 10. Software критерии

- Host golden model совпадает с firmware в пределах заданной fixed-point погрешности.
- Игра запускается из SD.
- Несколько `.bin` файлов выбираются и запускаются.
- Demo не портит best score.
- Ошибочный image не зависает в bootloader.

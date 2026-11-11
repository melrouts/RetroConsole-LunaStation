# Troubleshooting

## HDMI blank

Проверить питание, cable, monitor input, pixel clock, PLL lock, sync polarity и constraints. Сначала записать solid color test bitstream.

## SD не определяется

Проверить FAT16/FAT32, contacts, SPI mode, card initialization, voltage level и отсутствие floating chip select. Запустить SD block-read test.

## `.BIN` не отображается

Проверить extension, regular file attribute, FAT chain и максимальное количество entries. Убедиться, что имя не превышает лимит menu renderer.

## Image rejected

Проверить magic, format version, hardware ABI, image size, load address и CRC.

## PicoRV32 зависает

Проверить reset release, RAM mapping, stack, linker script, bus ready/valid и отсутствие доступа за пределами RAM.

## Tearing или артефакты

Проверить frame snapshot, задержку sync относительно pipeline и отсутствие обновления compositor state внутри active frame.

## Timing failure

Уменьшить глубину комбинационной логики, добавить pipeline register, сократить число параллельных проверок и повторить synthesis. Не снижать pixel clock без решения по HDMI timing.

## Нет звука

Для тестовой мелодии ESP32-приёмника с MAX98357A:

- Проверить питание усилителя, общий GND и соединения: LRC → GPIO25,
  BCLK → GPIO32, DIN → GPIO22. Менять проводку только при отключённом питании.
- При 115200 baud отправить приёмнику `status`, затем `sound`. `audio=ready`
  подтверждает готовность драйвера, но не динамика и не самой проводки.
- Динамик должен быть подключён только между выходами `+` и `−` усилителя;
  ни один из этих выходов нельзя соединять с GND.
- При жужжании или искажениях ещё раз сверить LRC, BCLK и DIN с прошивкой;
  несовпадение I²S-проводки и настроенных GPIO может испортить звук.
- Если мелодия слишком тихая или громкая, изменить `StartupChime::PEAK` в
  `examples/espnow-counter/espnow-counter-rx/startup_chime.h` и перепрошить
  приёмник. Учитывать допустимую мощность динамика.
- Если появляется `Brownout detector was triggered`, проверить USB-кабель,
  питание и общую землю. Не отключать защиту от просадки питания.

Для игрового звука нужны новые совместимые образы FPGA, `LUNAR.BIN` и ESP32.
В новой прошивке приёмника `audio-demo` демонстрирует музыку и эффекты без
игры; если демонстрация слышна, но игра молчит, проверить UART Tang TX FPGA26 →
ESP32 GPIO16, общую землю и журнал `AUDIO GAME`. Сообщение выводится при
изменении состояния, а не на каждый кадр. Без корректных аудиокадров
более 500 мс музыка и двигатель затихают. Старый FPGA не поддерживает
`AUDIO_LINK`: новый BIN остановится с `BOOT_STATUS=2`, а не запустит игру.
Порядок обновления и ограничения SRAM — в `10_BUILD_AND_UPDATE.md`.

Музыка должна играть на главном экране, заставках и в демо (громче) и в игре
(тише). В журнале приёмника это `AUDIO GAME scene=4 mode=attract` на главном
экране и заставках, `scene=1` или `5` (`flying`) в игре и `scene=6` или `7`
(`demo`) в демо. Если в игре музыка есть, а на главном экране, заставках и в
демо молчит, и в журнале повторяется `ERROR: invalid game audio frame 0x64`
(или `0x76`, `0x7f`), на ESP32 осталась прошивка без уровней музыки:
перепрошить приёмник текущей версией. Если музыка в игре слишком тихая или
громкая, изменить `MUSIC_GAME_GAIN` (в меню и демо — `MUSIC_MENU_GAIN`) в
`examples/espnow-counter/espnow-counter-rx/game_audio.h` и перепрошить
приёмник; общий предел громкости — `StartupChime::PEAK`.

В `index.html` музыка и эффекты синтезируются отдельно через Web Audio API
на устройстве браузера. Для запуска аудио может потребоваться нажатие
кнопки Play. Во время игры `M` переключает общий звук, `N` — музыку;
музыку также переключает кнопка MUSIC.
Этот браузерный тракт не использует интерфейс MAX98357A на ESP32.

## Кнопки срабатывают сами

Проверить pull-up/pull-down, debounce, input polarity и общий ground. Не оставлять input GPIO floating.

## Best score не сохраняется

Проверить наличие заранее созданного 32-byte `BEST.SAV`, block-write support,
CRC, generation counter и состояние питания во время записи. FAT metadata не
должна изменяться; при ошибке записи должна оставаться прежняя valid копия.

# Формат SD-карты

## 1. Файловая система

Первая рабочая версия использует FAT16 или FAT32 с MBR и секторами 512 bytes.
exFAT, GPT и ext4 не поддерживаются. Firmware читает directory/allocation
metadata, а при первом сохранении звуковых настроек создает `GAMES/LUNASET.CFG`
в свободной directory entry и выделяет для него один cluster. Настройки
обновляются на месте; updater по-прежнему пишет только заранее выделенные
sectors `UPDATEA.BIN`/`UPDATEB.BIN`. При отсутствии SD-карты или места для файла
меню работает с настройками по умолчанию в RAM.

Firmware должен читать:

- boot sector;
- FAT parameters;
- FAT chain;
- root directory или directory cluster;
- подкаталог `GAMES` и его FAT chain;
- regular files.

Поддерживаются short 8.3 names; LFN, скрытые/системные записи и подкаталоги
игнорируются при показе игр. FAT16 и FAT32 проверяются native-тестами с
фрагментированными каталогами и цепочками файлов. `LUNASET.CFG` — единственный
файл, который firmware создает и обновляет через FAT metadata; резервирования
и удаления файлов нет. Запись `BEST.SAV` не реализована.

## 2. Файлы

```text
/GAMES/LUNAR.BIN
/GAMES/UPDATEA.BIN
/GAMES/UPDATEB.BIN
/GAMES/OTHERGAME.BIN
/GAMES/AD.RLE
/GAMES/BEST.SAV
/GAMES/LUNASET.CFG (создается при первом сохранении настроек)
```

По указанию пользователя каталог игр — `GAMES` в корне карты, не root
directory. В game browser показываются только regular files этого каталога с
extension `.bin`, сравнение выполняется без учета регистра. Подкаталог
`GAMES/BACKUP`, volume labels, LFN, hidden/system entries пропускаются.
Рекурсивное сканирование и fallback к играм в корне не предусмотрены.

2026-11-02 карта `Luna9` обнаружена на macOS как writable FAT32 и на ней
создан `/GAMES`, без форматирования и удаления существующих файлов. Первый
образ `SMOKE.BIN` — диагностика CPU/RAM/MMIO, не игровая программа.
SD SPI/FAT boot подтвержден на этой карте в onboard socket Tang Nano 9K:
диагностический payload загружен с карты и выдал свежие UART PASS.
`build/images/LUNAR.BIN` — первый игровой прототип, уже записанный в `/GAMES`
с проверкой readback и запущенный на плате. SHA-256 файла:
`479c27389999bd47e0c751cc8973e24ad7f7ac2b81afb2a3fd2ef30f89aa040b`.
Пользователь подтвердил игровой экран и управление START/THRUST/поворот.
Обновление графики и angle contract записано с backup прежнего BIN;
пользователь подтвердил правильное вращение корпуса и главное меню.
BEST SCORE этого прототипа хранится только в RAM до перезапуска,
описанный ниже BEST.SAV остается целевым форматом, не готовой функцией.

При старте открывается главное меню с тремя видимыми названиями игр; кнопками
вверх/вниз выбирается любой regular `.BIN`, подтверждение запускает его, MENU
открывает настройки. При первом выборе по умолчанию выделяется `LUNAR.BIN`, если
он есть, иначе первый файл каталога. Валидный A/B update slot применяется
только при запуске `LUNAR.BIN`; `UPDATEA.BIN` и `UPDATEB.BIN` не показываются
как игры. Неверный image показывает ошибку и оставляет пользователя в меню.
Настройки музыки и эффектов сохраняются в `LUNASET.CFG` при выходе из меню
настроек. Если файла или свободного места нет, изменение действует до
перезапуска, но не мешает запуску игр.

Поддерживаются SDHC и byte-addressed SDSC, mode 0, sector CRC16; MBR
FAT16/FAT32, fragmented files/directories, ограниченный обход FAT chain.
Без SD-карты также открывается главное меню, отображается сообщение о карте и
периодически повторяется попытка подключения. Игры доступны после вставки
карты без перезагрузки.

## 3. Game image header v1

Header имеет 32 bytes. Все integer fields little-endian, magic хранится как
ASCII bytes `4C 55 4E 41` (`LUNA`). Payload начинается с offset 32.

```text
offset  size  field                    value/rule
0       4     magic                    ASCII "LUNA"
4       2     format_version           1
6       2     hardware_abi_version     1 for v1 bitstream
8       4     image_size               payload bytes, non-zero
12      4     load_address             validated RAM/PSRAM address
16      4     entry_point              validated executable address
20      4     flags                    reserved, must be 0 in v1
24      4     payload_crc32            CRC-32 of payload only
28      4     header_crc32             CRC-32 of bytes 0..27
```

Bootloader проверяет magic, exact format/ABI version for v1, size bounds,
load/entry range, header CRC и payload CRC до передачи управления.

`scripts/game_image.py pack/check` реализует host-сторону формата. RV32I
load/entry выровнены на 4 bytes, entry содержит полную 4-byte instruction
внутри payload. Размер файла равен ровно `32 + image_size`, trailing bytes
отклоняются. Текущий предел payload — RAM minus reserved stack (8192 - 1024 =
7168 bytes при load 0), получаемый из `hardware/platform_config.vh`.
BSS и stack дополнительно проверяет linker, так как header их не описывает.
Те же header/CRC vectors проверяются native C и настоящим PicoRV32 bootloader.

CRC algorithm: CRC-32/ISO-HDLC (Ethernet), polynomial `0x04C11DB7`, reflected
input/output, initial value `0xFFFFFFFF`, final XOR `0xFFFFFFFF`. The standard
check value for ASCII `123456789` is `0xCBF43926`. Packer and bootloader must
share test vectors for empty payload, one-byte payload and the check string.

## 4. Advertisement asset

v1 asset format: `AD.RLE`, logical resolution 320x240, RGB565 little-endian.
The 20-byte file header is:

```text
offset  size  field              value/rule
0       4     magic              ASCII "ADRL"
4       2     format_version     1
6       2     width              320
8       2     height             240
10      2     reserved           0
12      4     payload_size       compressed payload bytes
16      4     payload_crc32      CRC-32 of compressed payload
```

The RLE payload starts at offset 20. Each packet is 3 bytes: two-byte pixel
value followed by one-byte run length from 1 to 255. Decoder validates the
header and CRC, expands exactly 76800 pixels, and rejects early EOF, overflow
and trailing data. Tool `pack_ad.py` выполняет:

1. чтение PNG/JPEG на PC;
2. resize до согласованного размера;
3. conversion RGB565;
4. RLE compression;
5. header и CRC.

Максимальный compressed size задается в hardware configuration. При отсутствии
или ошибке asset использовать встроенный placeholder.

## 5. Best score

`BEST.SAV` имеет ровно 32 bytes и создается packer-ом заранее. Он содержит две
одинаковые 16-byte записи; offsets ниже указаны относительно начала каждой
записи, а вторая запись начинается с file offset 16:

```text
offset  size  field
0       4     magic ASCII "BEST"
4       1     version = 1
5       1     generation modulo 256
6       2     reserved = 0
8       4     score uint32 little-endian
12      4     CRC-32 of bytes 0..11
```

Firmware выбирает последнюю valid запись с учетом modulo-256 generation. Если
обе записи невалидны, используется score 0. Если generation values различаются,
новее та, для которой `(candidate - other) mod 256` находится в диапазоне
1..127; при равенстве выбирается первая запись. При обновлении сначала
записывается неактивная копия, затем она перечитывается и проверяется. Ошибка
block write оставляет прежнюю valid запись активной.

## 6. SD update rules

- Не форматировать карту скриптами автоматически.
- Перед копированием проверять image size и CRC.
- Сохранять backup предыдущего `.BIN`.
- Не переименовывать файл во время загрузки платы.
- При несовместимом ABI показывать error state.

`scripts/deploy_game.py` пишет только в `GAMES` существующего mounted volume,
проверяет образ до копирования и readback после записи. При замене прежний
файл сохраняется в `GAMES/BACKUP/<8 hex digits>.BAK`; конфликт backup names
прерывает замену. Временная копия имеет `.TMP`, а не `.BIN`. Скрипт не
форматирует, не размонтирует и не изменяет raw sectors карты. Перед извлечением
карты пользоваться штатным безопасным извлечением ОС.

## 7. A/B slots обновления по UART

Оба файла `GAMES/UPDATEA.BIN` и `GAMES/UPDATEB.BIN` имеют ровно 8192 bytes
(16 sectors). Это контейнеры, не обычные LUNA images. Их один раз создает
`scripts/provision_updates.py` на mounted PC card. Существующие slots
правильного размера сохраняются без изменений, включая ранее записанные игры.

Sector 0 содержит 32-byte commit record (остальной sector заполнен нулями):

```text
offset  size  field
0       4     ASCII "UPD1"
4       4     generation uint32, nonzero
8       4     full LUNA file size, 36..7200
12      4     CRC32 всего LUNA файла, включая header
16      12    reserved = 0
28      4     CRC32 bytes 0..27
```

Sectors 1..15 содержат LUNA image; неиспользованный хвост записываемого
sector обнуляется. Все integer fields little-endian, CRC тот же ISO-HDLC.
Проверяются commit CRC, header/ABI/bounds, полный CRC файла и payload CRC.
Generation не оборачивается: при `UINT32_MAX` обновление отклоняется.
При одинаковых generation выбирается A; следующий update пишет B.

Loader отображает FAT chains на реальные sectors, поддерживает fragmentation,
отклоняет короткие/циклические chains, пересечение A/B, factory LUNAR и
root/GAMES directories. Запись update slots не изменяет boot sector, FAT или
directory entries; только сохранение `LUNASET.CFG` выделяет один новый cluster.
Предполагается исправная FAT-карта; это не filesystem repair/checker для
произвольно поврежденных cross-links других файлов.

Пишется только более старый/пустой slot: сначала его commit sector
инвалидируется, затем каждый data sector записывается CMD24 с CRC16 и
перечитывается для сравнения. Commit sector пишется последним, затем весь slot
повторно валидируется. Прежний активный slot и `LUNAR.BIN` не перезаписываются.
Невалидный/оборванный slot при следующем запуске пропускается; реальная ошибка
SD read не маскируется как отсутствие обновления. Такая схема защищает от
незавершенной записи slot, но не гарантирует сохранность при внутреннем сбое
контроллера SD, способном повредить другие sectors.

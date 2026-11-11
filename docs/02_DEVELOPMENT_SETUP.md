# Установка development environment на Windows и macOS

## 1. Назначение

Этот документ описывает инструменты для:

- разработки Verilog/SystemVerilog;
- сборки PicoRV32 firmware;
- моделирования и RTL-тестирования;
- упаковки SD-карты;
- synthesis и programming Tang Nano 9K.

Перед установкой запустить checker для своей операционной системы:

### Windows

```powershell
.\scripts\check-prerequisites.ps1
```

Если Windows PowerShell блокирует локальные scripts политикой execution policy, использовать временный режим только для текущего процесса:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\check-prerequisites.ps1
```

Системную execution policy менять не требуется.

### macOS

```bash
chmod +x scripts/check-prerequisites.sh
./scripts/check-prerequisites.sh
```

Checker не устанавливает программы и не изменяет систему. Он выводит название инструмента, версию и статус: зеленый `[OK]` или красный `[MISSING]`.

## 2. Набор инструментов

### Общие инструменты

- Git;
- Python 3.11+;
- Node.js LTS;
- RISC-V bare-metal GCC/binutils для `riscv32`;
- GNU Make или Python build driver;
- Verilator;
- Icarus Verilog;
- GTKWave;
- pytest;
- Pillow;
- optional pyserial;
- clang-format или Verible.

### FPGA-инструменты

- Yosys;
- native `nextpnr-himbaechel` с Gowin support из OSS CAD Suite;
- `gowin_pack`;
- `openFPGALoader` для Gowin JTAG;
- официальная схема и pinout Tang Nano 9K.

Для этой платы можно использовать CLI toolchain, уже проверенный в проекте
E26: Yosys + native `nextpnr-himbaechel` + `gowin_pack`, а для записи через onboard
USB-JTAG — `openFPGALoader`. Gowin EDA IDE/Programmer остается альтернативой,
а не обязательной зависимостью этого CLI workflow. Проприетарный Gowin EDA,
если он используется, устанавливается вручную из официального источника.

## 3. Windows

### 3.1 Обязательные программы

Рекомендуется установить:

- Git for Windows;
- Python 3.11 или новее с добавлением в PATH;
- Node.js LTS;
- MSYS2 для Unix-подобных build utilities;
- RISC-V bare-metal toolchain;
- Verilator, Icarus Verilog и GTKWave;
- Gowin EDA и Programmer вручную.

### 3.2 Установка через winget

Проверить доступные package IDs:

```powershell
winget search Git.Git
winget search Python.Python
winget search OpenJS.NodeJS.LTS
winget search MSYS2
```

Установить базовые инструменты:

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.12 -e
winget install --id OpenJS.NodeJS.LTS -e
winget install --id MSYS2.MSYS2 -e
```

Если package ID изменился, использовать результат `winget search`, а затем повторно запустить checker.

### 3.3 MSYS2 tools

Открыть MSYS2 UCRT64 terminal и обновить packages:

```bash
pacman -Syu
pacman -S --needed make mingw-w64-ucrt-x86_64-verilator \
  mingw-w64-ucrt-x86_64-iverilog \
  mingw-w64-ucrt-x86_64-gtkwave
```

Добавить соответствующий `ucrt64/bin` в PATH только если инструменты должны запускаться из PowerShell. Иначе выполнять simulation из MSYS2 UCRT64 terminal.

### 3.4 RISC-V toolchain

Выбрать один bare-metal toolchain и не смешивать его с другими версиями в PATH. Поддерживаемые имена compiler executable:

```text
riscv-none-elf-gcc
riscv32-unknown-elf-gcc
riscv-none-embed-gcc
riscv64-elf-gcc
```

После ручной установки добавить каталог `bin` в PATH и проверить:

```powershell
riscv-none-elf-gcc --version
riscv-none-elf-objcopy --version
```

Для Homebrew `riscv64-elf-gcc` и `riscv64-elf-objcopy` подходят, если toolchain
содержит multilib `rv32i/ilp32`. Фактически выбранные имена зафиксировать в
локальном toolchain configuration file.

Для всех baseline firmware builds использовать одинаковый target contract:

```text
-march=rv32i -mabi=ilp32
```

`rv32im` допускается только после явного включения multiplier в RTL и обновления
hardware feature contract. Не использовать floating-point ABI. Проверить target
командой `riscv-none-elf-gcc -Q --help=target` (или эквивалентом выбранного
prefix) и сохранить вывод вместе с build log.

### 3.5 Python environment

Из PowerShell в корне проекта:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install pytest Pillow
```

Если политика PowerShell запрещает activation script, использовать:

```powershell
.\.venv\Scripts\python.exe -m pip install pytest Pillow
```

### 3.6 Gowin EDA

1. Скачать версию Gowin EDA для Tang Nano 9K.
2. Установить IDE и Programmer.
3. Установить USB/JTAG driver.
4. Открыть sample project.
5. Проверить обнаружение платы.
6. Сохранить путь в локальной переменной `GOWIN_EDA_HOME`.
7. Запустить checker.

Локальные пути и license information не коммитить.

## 4. macOS

### 4.1 Homebrew

Установить Homebrew с официального сайта, затем:

```bash
brew update
brew install git python node make verilator iverilog gtkwave
```

Проверить наличие formula перед установкой, если Homebrew сообщает, что package переименован:

```bash
brew search verilator
brew search iverilog
brew search gtkwave
```

### 4.2 Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install pytest Pillow
```

### 4.3 RISC-V toolchain

Вариант через Homebrew, если formula доступна в текущем окружении:

```bash
brew search riscv
brew install riscv64-elf-gcc
```

Если formula отсутствует, скачать один проверенный bare-metal RISC-V release, добавить его `bin` в PATH и проверить:

```bash
riscv64-elf-gcc --version
riscv64-elf-objcopy --version
```

Выбранный toolchain должен быть тем же, что используется на Windows, либо его отличия должны быть зафиксированы в build documentation.

### 4.4 Ограничение Gowin EDA

Gowin EDA IDE/Programmer может не иметь полноценной официальной поддержки
macOS, но для Tang Nano 9K существует альтернативный CLI workflow с
open-source tools. Использовать Gowin IDE/Programmer только если нужна
конкретная возможность, отсутствующая в CLI workflow; не считать Gowin IDE
единственным способом программирования платы.

### 4.5 CLI synthesis и JTAG programming

Рабочий Makefile E26 использует native `nextpnr-himbaechel`, Yosys и
`gowin_pack` из OSS CAD Suite; `openFPGALoader` обслуживает onboard USB-JTAG.
WASM `yowasp-nextpnr-gowin` оказался не рабочей цепочкой E26 и для этого проекта
не требуется. Makefile принимает `OSS_CAD_SUITE`; default — тот же каталог,
что в E26:

```bash
export OSS_CAD_SUITE="$HOME/.local/share/electron26-fpga-download/oss-cad-suite"
"$OSS_CAD_SUITE/bin/yosys" -V
"$OSS_CAD_SUITE/bin/nextpnr-himbaechel" --version
"$OSS_CAD_SUITE/bin/gowin_pack" --help
openFPGALoader --version
openFPGALoader --scan-usb
openFPGALoader -b tangnano9k --detect
```

Для версии с LiteX target сборки E26 использовалась команда
`make -C Electron26.TangNano9K litex-bitstream`. Это команда именно E26, не
этого проекта: перед ее запуском нужны исходники и Makefile E26. Установка CLI
tools сама по себе не создает platform top, pin constraints, bootloader или
flash manager для Lunar Lander.

На этой macOS проверены native Yosys `0.70+286`, nextpnr
`0.11.1-84-g5e1b0f15` и `openFPGALoader v1.2.0`. Команда `make bitstream`
успешно выполнила synthesis/place-and-route/packing минимального PicoRV32 top;
собранный `.fs` запущен через SRAM и выдал два `PASS` по UART.

Linux может использоваться для firmware и simulation; команды установки Gowin
и совместимость конкретной версии с Linux должны быть подтверждены отдельно.
Checker не трактует наличие `gw_sh` как доказательство корректного device
support или license setup.

## 5. Checker scripts

```text
scripts/check-prerequisites.ps1
scripts/check-prerequisites.sh
```

Оба скрипта проверяют:

- Git;
- Python;
- Node.js;
- RISC-V GCC и objcopy, включая имена Homebrew `riscv64-elf-gcc` и
  `riscv64-elf-objcopy`;
- Make;
- Verilator;
- Icarus Verilog;
- GTKWave;
- Python modules `pytest` и `Pillow`;
- Gowin через `GOWIN_EDA_HOME`, `GW_SH` или executable `gw_sh`/`gw_sh.exe`;
- Programmer через `programmer`/`programmer.exe` или `GOWIN_EDA_HOME`.

Статусы:

- зеленый `[OK]` — найдено и версия прочитана;
- красный `[MISSING]` — не найдено или не проверяется;
- желтый `[INFO]` — optional/manual check.

Checker не проверяет Yosys, `nextpnr-himbaechel`, `gowin_pack` или
`openFPGALoader`. Отсутствие Gowin EDA отображается как `[INFO]` и само по себе
не означает, что CLI synthesis/JTAG workflow недоступен; проверить перечисленные
CLI executables вручную по разделу 4.5.

Скрипты не должны:

- устанавливать программы;
- менять PATH;
- удалять существующие установки;
- форматировать SD-карты;
- хранить credentials;
- требовать administrator/root privileges.

## 6. После установки

Выполнить checker и сохранить его вывод в issue или build log. Затем проверить:

```text
Git version
Python version
Node version
RISC-V compiler and objcopy
Verilator
Icarus Verilog
GTKWave
pytest/Pillow
Gowin EDA/Programmer status
```

Если Gowin EDA отсутствует, использовать native OSS CAD Suite и
`openFPGALoader` по разделу 4.5. Отсутствие проприетарного Programmer не
блокирует CLI synthesis или JTAG SRAM programming. Release acceptance и
постоянная запись требуют отдельных проверок из `05_SYNTHESIS_AND_PROGRAMMING.md`.

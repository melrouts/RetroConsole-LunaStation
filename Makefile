OSS_CAD_SUITE ?= $(HOME)/.local/share/electron26-fpga-download/oss-cad-suite
YOSYS ?= $(OSS_CAD_SUITE)/bin/yosys
NEXTPNR ?= $(OSS_CAD_SUITE)/bin/nextpnr-himbaechel
PACK ?= $(OSS_CAD_SUITE)/bin/gowin_pack
LOADER ?= openFPGALoader
RISCV_PREFIX ?= riscv64-elf-
PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator

RAM_BYTES := $(shell awk '/^`define MAIN_RAM_BYTES / {print $$3}' hardware/platform_config.vh)
STACK_BYTES := $(shell awk '/^`define STACK_BYTES / {print $$3}' hardware/platform_config.vh)
BOOT_BASE := $(shell awk '/^`define BOOT_BASE / {print $$3}' hardware/platform_config.vh)
BOOT_CODE_BYTES := $(shell awk '/^`define BOOT_CODE_BYTES / {print $$3}' hardware/platform_config.vh)
BOOT_RAM_BYTES := $(shell awk '/^`define BOOT_RAM_BYTES / {print $$3}' hardware/platform_config.vh)
RTL := rtl/reset_sync.sv rtl/memory_map.sv rtl/picorv32_wrapper.sv \
       rtl/smoke_soc.sv rtl/sd_spi.sv rtl/uart_tx.sv rtl/uart_report.sv rtl/tangnano9k_smoke.sv
CPU := third_party/picorv32/picorv32.v
VIDEO_CORE := rtl/video_timing.sv rtl/video_pattern.sv rtl/font_rom.sv rtl/tmds_encoder.sv
VIDEO_RTL := $(filter-out rtl/tangnano9k_smoke.sv,$(RTL)) $(VIDEO_CORE) \
             rtl/uart_rx.sv rtl/uart_buttons.sv rtl/uart_buttons_merge.sv rtl/uart_update.sv rtl/uart_link_tx.sv rtl/video_snapshot.sv rtl/video_art.sv rtl/video_memorial.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv rtl/video_game.sv \
             rtl/gowin_video_output.sv rtl/console_core.sv rtl/tangnano9k_video.sv
CONSOLE_RTL := $(filter-out rtl/tangnano9k_video.sv,$(VIDEO_RTL)) rtl/tangnano9k_console.sv
BOOT_SOURCES := firmware/start.S firmware/boot.c firmware/sd.c firmware/fat.c firmware/image.c firmware/update.c
FIRMWARE_FLAGS := -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin \
                  -nostdlib -Wall -Wextra -Werror -Wl,--build-id=none \
                  -Wl,--defsym=MAIN_RAM_BYTES=$(RAM_BYTES) \
                  -Wl,--defsym=STACK_BYTES=$(STACK_BYTES) \
                  -Wl,-Map,build/smoke.map -T firmware/linker.ld

.PHONY: all test test-verilator lint bitstream load-sram video-bitstream video-lint images deploy-smoke
all: test

build:
	mkdir -p build

build/smoke.elf: firmware/start.S firmware/smoke.c firmware/mmio.h firmware/linker.ld hardware/platform_config.vh Makefile | build
	$(RISCV_PREFIX)gcc $(FIRMWARE_FLAGS) firmware/start.S firmware/smoke.c -o $@
	$(RISCV_PREFIX)size $@

build/smoke.bin: build/smoke.elf
	$(RISCV_PREFIX)objcopy -O binary $< $@

build/smoke.hex: build/smoke.bin scripts/bin_to_hex.py hardware/platform_config.vh
	$(PYTHON) scripts/bin_to_hex.py $< $@ --ram-bytes $(RAM_BYTES)

build/boot.elf: $(BOOT_SOURCES) firmware/boot.ld firmware/fat.h firmware/image.h firmware/update.h firmware/sd.h firmware/mmio.h hardware/platform_config.vh Makefile | build
	$(RISCV_PREFIX)gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin \
		-nostdlib -Wall -Wextra -Werror -Wl,--build-id=none -T firmware/boot.ld \
		-DMAIN_RAM_BYTES=$(RAM_BYTES) -DSTACK_BYTES=$(STACK_BYTES) \
		-Wl,--defsym=BOOT_BASE=$(BOOT_BASE) -Wl,--defsym=BOOT_CODE_BYTES=$(BOOT_CODE_BYTES) \
		-Wl,--defsym=BOOT_RAM_BYTES=$(BOOT_RAM_BYTES) -Wl,--defsym=STACK_BYTES=$(STACK_BYTES) \
		-Wl,-Map,build/boot.map $(BOOT_SOURCES) -lgcc -o $@
	$(RISCV_PREFIX)size $@

build/boot.bin: build/boot.elf
	$(RISCV_PREFIX)objcopy -O binary $< $@

build/boot.hex: build/boot.bin scripts/bin_to_hex.py hardware/platform_config.vh
	$(PYTHON) scripts/bin_to_hex.py $< $@ --ram-bytes $(BOOT_RAM_BYTES)

build/images:
	mkdir -p $@

build/images/SMOKE.BIN: build/smoke.bin scripts/game_image.py hardware/platform_config.vh | build/images
	$(PYTHON) scripts/game_image.py pack $< $@

images: build/images/SMOKE.BIN build/images/LUNAR.BIN

build/sine_table.h: scripts/sine_table.py | build
	$(PYTHON) scripts/sine_table.py

build/lunar.elf: firmware/start.S firmware/game.c firmware/game_engine.c firmware/runtime.c firmware/game_engine.h firmware/mmio.h firmware/linker.ld hardware/platform_config.vh build/sine_table.h Makefile
	$(RISCV_PREFIX)gcc -march=rv32i -mabi=ilp32 -Oz -msave-restore \
		-ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
		-nostdlib -Wall -Wextra -Werror -Ibuild -Wl,--build-id=none \
		-T firmware/linker.ld -Wl,--gc-sections -Wl,--defsym=MAIN_RAM_BYTES=$(RAM_BYTES) \
		-Wl,--defsym=STACK_BYTES=$(STACK_BYTES) -Wl,-Map,build/lunar.map \
		firmware/start.S firmware/game.c firmware/game_engine.c firmware/runtime.c -lgcc -o $@
	$(RISCV_PREFIX)size $@

build/lunar.raw: build/lunar.elf
	$(RISCV_PREFIX)objcopy -O binary $< $@

build/images/LUNAR.BIN: build/lunar.raw scripts/game_image.py hardware/platform_config.vh | build/images
	$(PYTHON) scripts/game_image.py pack $< $@

.PHONY: deploy-games
deploy-games: images
	$(PYTHON) scripts/deploy_game.py build/images/SMOKE.BIN --volume "$(SD_VOLUME)"
	$(PYTHON) scripts/deploy_game.py build/images/LUNAR.BIN --volume "$(SD_VOLUME)"

SD_VOLUME ?= /Volumes/Luna9
deploy-smoke: build/images/SMOKE.BIN
	$(PYTHON) scripts/deploy_game.py $< --volume "$(SD_VOLUME)"

build/font.hex: third_party/font8x8/font8x8_basic.h scripts/font_to_hex.py | build
	$(PYTHON) scripts/font_to_hex.py $< $@

build/hud-font.hex: third_party/font8x8/font8x8_basic.h scripts/font_to_hex.py | build
	$(PYTHON) scripts/font_to_hex.py $< $@ --hud

build/lander.hex: scripts/video_assets.py | build
	$(PYTHON) scripts/video_assets.py

build/earth.hex: build/lander.hex
	@test -f $@ || $(PYTHON) scripts/video_assets.py

build/memorial.hex: scripts/memorial_assets.py photos/luna9-capsule.jpg photos/apollo11-nasa-6900956.jpg | build
	$(PYTHON) scripts/memorial_assets.py

build/memorial-text.hex: scripts/memorial_assets.py build/memorial.hex
	$(PYTHON) scripts/memorial_assets.py

build/video.vvp: tests/tb_video.sv $(VIDEO_CORE) build/font.hex
	$(IVERILOG) -g2012 -s tb_video -o $@ tests/tb_video.sv $(VIDEO_CORE)

build/font-rom.vvp: tests/tb_font_rom.sv rtl/font_rom.sv rtl/game_font_rom.sv build/font.hex build/hud-font.hex
	$(IVERILOG) -g2012 -s tb_font_rom -o $@ tests/tb_font_rom.sv rtl/font_rom.sv rtl/game_font_rom.sv

build/tmds.vvp: tests/tb_tmds.sv rtl/tmds_encoder.sv | build
	$(IVERILOG) -g2012 -s tb_tmds -o $@ $^

build/spi.vvp: tests/tb_sd_spi.sv rtl/sd_spi.sv | build
	$(IVERILOG) -g2012 -s tb_sd_spi -o $@ $^

build/test-card.hex: tests/generate_sd_card.py tests/test_native_boot.py build/images/SMOKE.BIN
	$(PYTHON) tests/generate_sd_card.py build/images/SMOKE.BIN

build/game-card.hex: tests/generate_sd_card.py tests/test_native_boot.py build/images/LUNAR.BIN build/images/SMOKE.BIN
	$(PYTHON) tests/generate_sd_card.py build/images/LUNAR.BIN --game

UPDATE_RTL := rtl/uart_update.sv rtl/uart_rx.sv
build/sd-boot.vvp: tests/tb_sd_boot.sv tests/sd_card_model.sv $(RTL) $(CPU) $(UPDATE_RTL) rtl/video_snapshot.sv build/boot.hex build/test-card.hex build/game-card.hex hardware/platform_config.vh
	$(IVERILOG) -g2012 -I hardware -s tb_sd_boot -o $@ tests/tb_sd_boot.sv tests/sd_card_model.sv $(RTL) $(CPU) $(UPDATE_RTL) rtl/video_snapshot.sv

.PHONY: test-boot
test-boot: build/sd-boot.vvp
	$(VVP) build/sd-boot.vvp
	$(VVP) build/sd-boot.vvp +bad-crc

.PHONY: test-game-boot
build/verilator-boot/Vtb_sd_boot: tests/tb_sd_boot.sv tests/sd_card_model.sv $(RTL) $(CPU) $(UPDATE_RTL) rtl/video_snapshot.sv tests/vendor_lint.vlt build/boot.hex build/test-card.hex build/game-card.hex hardware/platform_config.vh
	$(VERILATOR) --binary --timing --timescale 1ns/1ps -Ihardware \
		--top-module tb_sd_boot --Mdir build/verilator-boot tests/vendor_lint.vlt \
		tests/tb_sd_boot.sv tests/sd_card_model.sv $(RTL) $(UPDATE_RTL) rtl/video_snapshot.sv -v $(CPU)

test-game-boot: build/verilator-boot/Vtb_sd_boot
	build/verilator-boot/Vtb_sd_boot +game
	build/verilator-boot/Vtb_sd_boot +game +bad-crc
	build/verilator-boot/Vtb_sd_boot +game +no-audio

.PHONY: test-update
test-update: build/verilator-boot/Vtb_sd_boot
	build/verilator-boot/Vtb_sd_boot +game +update
	build/verilator-boot/Vtb_sd_boot +game +update +write-reject

build/input.vvp: tests/tb_input_control.sv rtl/reset_sync.sv rtl/button_debounce.sv | build
	$(IVERILOG) -g2012 -s tb_input_control -o $@ $^

build/smoke.vvp: tests/tb_smoke_soc.sv $(RTL) $(CPU) build/smoke.hex hardware/platform_config.vh
	$(IVERILOG) -g2012 -I hardware -s tb_smoke_soc -o $@ tests/tb_smoke_soc.sv $(RTL) $(CPU)

build/memory.vvp: tests/tb_memory_map.sv rtl/memory_map.sv build/smoke.hex hardware/platform_config.vh
	$(IVERILOG) -g2012 -I hardware -s tb_memory_map -o $@ tests/tb_memory_map.sv rtl/memory_map.sv

build/uart-buttons.vvp: tests/tb_uart_buttons.sv rtl/uart_buttons.sv rtl/uart_rx.sv hardware/platform_config.vh | build
	$(IVERILOG) -g2012 -I hardware -s tb_uart_buttons -o $@ tests/tb_uart_buttons.sv rtl/uart_buttons.sv rtl/uart_rx.sv

build/uart-buttons-merge.vvp: tests/tb_uart_buttons_merge.sv rtl/uart_buttons_merge.sv rtl/uart_buttons.sv rtl/uart_rx.sv hardware/platform_config.vh | build
	$(IVERILOG) -g2012 -I hardware -s tb_uart_buttons_merge -o $@ tests/tb_uart_buttons_merge.sv rtl/uart_buttons_merge.sv rtl/uart_buttons.sv rtl/uart_rx.sv

build/uart-report.vvp: tests/tb_uart_report.sv rtl/uart_report.sv rtl/uart_tx.sv rtl/uart_rx.sv hardware/platform_config.vh | build
	$(IVERILOG) -g2012 -I hardware -s tb_uart_report -o $@ tests/tb_uart_report.sv rtl/uart_report.sv rtl/uart_tx.sv rtl/uart_rx.sv

build/uart-update.vvp: tests/tb_uart_update.sv rtl/uart_update.sv rtl/uart_rx.sv rtl/uart_tx.sv | build
	$(IVERILOG) -g2012 -s tb_uart_update -o $@ $^

build/uart-rx.vvp: tests/tb_uart_rx.sv rtl/uart_rx.sv | build
	$(IVERILOG) -g2012 -s tb_uart_rx -o $@ $^

build/uart-link-tx.vvp: tests/tb_uart_link_tx.sv rtl/uart_link_tx.sv rtl/uart_tx.sv rtl/uart_rx.sv | build
	$(IVERILOG) -g2012 -s tb_uart_link_tx -o $@ $^

build/snapshot.vvp: tests/tb_video_snapshot.sv rtl/video_snapshot.sv | build
	$(IVERILOG) -g2012 -s tb_video_snapshot -o $@ $^

build/video-game.vvp: tests/tb_video_game.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv build/font.hex build/hud-font.hex build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex
	$(IVERILOG) -g2012 -s tb_video_game -o $@ tests/tb_video_game.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv

build/video-art.vvp: tests/tb_video_art.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv build/font.hex build/hud-font.hex build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex
	$(IVERILOG) -g2012 -s tb_video_art -o $@ tests/tb_video_art.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv

build/video-result.vvp: tests/tb_video_result.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv build/font.hex build/hud-font.hex build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex
	$(IVERILOG) -g2012 -s tb_video_result -o $@ tests/tb_video_result.sv rtl/video_game.sv rtl/video_memorial.sv rtl/video_art.sv rtl/font_rom.sv rtl/game_font_rom.sv rtl/velocity_arrow.sv rtl/hud_glyph_column.sv rtl/reason_rows.sv

.PHONY: test-velocity-arrow test-hud-glyph-column test-reason-rows
test-velocity-arrow:
	$(YOSYS) -Q -T -q -p 'read_verilog -sv rtl/velocity_arrow.sv tests/tb_velocity_arrow.sv; prep -flatten -top tb_velocity_arrow; sat -verify -prove equivalent 1'
	@echo "PASS: velocity arrow matches the original at all coordinates and headings"

test-hud-glyph-column:
	$(YOSYS) -Q -T -q -p 'read_verilog -sv rtl/hud_glyph_column.sv tests/tb_hud_glyph_column.sv; prep -flatten -top tb_hud_glyph_column; sat -verify -prove equivalent 1'
	@echo "PASS: HUD character columns match at all coordinates"

test-reason-rows:
	$(YOSYS) -Q -T -q -p 'read_verilog -sv rtl/reason_rows.sv tests/tb_reason_rows.sv; prep -flatten -top tb_reason_rows; sat -verify -prove equivalent 1'
	@echo "PASS: failure reason rows match for every cause"

test: test-velocity-arrow test-hud-glyph-column test-reason-rows build/input.vvp build/smoke.vvp build/memory.vvp build/video.vvp build/font-rom.vvp build/tmds.vvp build/spi.vvp build/uart-rx.vvp build/uart-buttons.vvp build/uart-buttons-merge.vvp build/uart-report.vvp build/uart-update.vvp build/uart-link-tx.vvp build/snapshot.vvp build/video-game.vvp build/video-art.vvp build/video-result.vvp build/sine_table.h
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'
	$(VVP) build/input.vvp
	$(VVP) build/memory.vvp
	$(VVP) build/smoke.vvp
	$(VVP) build/tmds.vvp
	$(VVP) build/video.vvp
	$(VVP) build/font-rom.vvp
	$(VVP) build/spi.vvp
	$(VVP) build/uart-rx.vvp
	$(VVP) build/uart-buttons.vvp
	$(VVP) build/uart-buttons-merge.vvp
	$(VVP) build/uart-report.vvp
	$(VVP) build/uart-update.vvp
	$(VVP) build/uart-link-tx.vvp
	$(VVP) build/snapshot.vvp
	$(VVP) build/video-game.vvp
	$(VVP) build/video-art.vvp
	$(VVP) build/video-result.vvp

test-verilator: build/smoke.hex
	$(VERILATOR) --binary --timing --timescale 1ns/1ps -Ihardware \
		--top-module tb_smoke_soc --Mdir build/verilator \
		tests/vendor_lint.vlt tests/tb_smoke_soc.sv $(RTL) -v $(CPU)
	build/verilator/Vtb_smoke_soc

lint:
	$(VERILATOR) --lint-only --Wall --top-module reset_sync rtl/reset_sync.sv
	$(VERILATOR) --lint-only --Wall --top-module button_debounce rtl/button_debounce.sv
	$(VERILATOR) --lint-only --Wall --timescale 1ns/1ps -Ihardware \
		--top-module tangnano9k_smoke tests/vendor_lint.vlt $(RTL) -v $(CPU)

build/smoke.json: $(RTL) $(CPU) hardware/platform_config.vh build/smoke.hex Makefile
	@echo "ABC carry-network and internal delay warnings are mapping estimates; post-route timing is gated separately."
	$(YOSYS) -Q -l build/synthesis.log -p 'read_verilog -sv -Ihardware $(RTL) $(CPU); synth_gowin -top tangnano9k_smoke -json $@; check -assert'

build/smoke.pnr.json: build/smoke.json hardware/tangnano9k-smoke.cst hardware/tangnano9k-smoke.sdc Makefile
	$(NEXTPNR) --json $< --write $@ --device GW1NR-LV9QN88PC6/I5 \
		--vopt family=GW1N-9C --vopt cst=hardware/tangnano9k-smoke.cst \
		--sdc hardware/tangnano9k-smoke.sdc --freq 27 --seed 1 \
		--report build/timing.json --log build/place-route.log

build/smoke.fs: build/smoke.pnr.json scripts/check_timing.py Makefile
	$(PYTHON) scripts/check_timing.py build/timing.json
	@echo "Packer optional numpy/msgspec/fastcrc warnings affect speed, not bitstream features."
	$(PACK) -d GW1N-9C -o $@ $<
	shasum -a 256 $@ > build/smoke.fs.sha256
	shasum -a 256 Makefile scripts/*.py tests/*.sv tests/*.py tests/*.vlt \
		$(RTL) $(CPU) firmware/* hardware/platform_config.vh \
		hardware/tangnano9k-smoke.cst hardware/tangnano9k-smoke.sdc \
		build/smoke.elf build/smoke.bin > build/sources.sha256
	$(YOSYS) -V > build/tool-versions.txt
	$(NEXTPNR) --version >> build/tool-versions.txt 2>&1
	$(RISCV_PREFIX)gcc --version >> build/tool-versions.txt
	$(LOADER) --version >> build/tool-versions.txt

bitstream: test lint build/smoke.fs

load-sram: bitstream
	$(LOADER) -b tangnano9k --write-sram build/smoke.fs

video-lint:
	$(VERILATOR) --lint-only --Wall --timescale 1ns/1ps -Ihardware \
		--top-module tangnano9k_video tests/vendor_lint.vlt tests/gowin_lint.vlt \
		$(VIDEO_RTL) -v $(CPU) -v $(OSS_CAD_SUITE)/share/yosys/gowin/cells_sim.v \
		-v $(OSS_CAD_SUITE)/share/yosys/gowin/cells_xtra_gw1n.v

build/video.json: $(VIDEO_RTL) $(CPU) hardware/platform_config.vh build/smoke.hex build/font.hex build/hud-font.hex build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex Makefile
	$(YOSYS) -Q -l build/video-synthesis.log -p 'read_verilog -sv -Ihardware $(VIDEO_RTL) $(CPU); synth_gowin -top tangnano9k_video -json $@; check -assert'

build/video.pnr.json: build/video.json hardware/tangnano9k-video.cst hardware/tangnano9k-video.sdc Makefile
	$(NEXTPNR) --json $< --write $@ --device GW1NR-LV9QN88PC6/I5 \
		--vopt family=GW1N-9C --vopt cst=hardware/tangnano9k-video.cst \
		--sdc hardware/tangnano9k-video.sdc --freq 27 --seed 1 \
		--report build/video-timing.json --log build/video-place-route.log

build/video.fs: build/video.pnr.json scripts/check_timing.py Makefile
	$(PYTHON) scripts/check_timing.py build/video-timing.json --min-mhz 25.2 \
		--expect-mhz 27 --expect-mhz 25.2
	$(PACK) -d GW1N-9C -o $@ $<
	shasum -a 256 $@ > build/video.fs.sha256
	shasum -a 256 Makefile scripts/*.py tests/*.sv tests/*.py tests/*.vlt \
		$(VIDEO_RTL) $(CPU) third_party/font8x8/font8x8_basic.h \
		firmware/* hardware/platform_config.vh hardware/tangnano9k-video.* \
		build/smoke.elf build/smoke.bin build/font.hex build/hud-font.hex > build/video-sources.sha256

video-bitstream: test lint video-lint build/video.fs

.PHONY: console-lint console-bitstream
console-lint:
	$(VERILATOR) --lint-only --Wall --timescale 1ns/1ps -Ihardware \
		--top-module tangnano9k_console tests/vendor_lint.vlt tests/gowin_lint.vlt \
		$(CONSOLE_RTL) -v $(CPU) -v $(OSS_CAD_SUITE)/share/yosys/gowin/cells_sim.v \
		-v $(OSS_CAD_SUITE)/share/yosys/gowin/cells_xtra_gw1n.v

build/console.json: $(CONSOLE_RTL) $(CPU) hardware/platform_config.vh build/smoke.hex build/font.hex build/hud-font.hex build/boot.hex build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex Makefile
	$(YOSYS) -Q -l build/console-synthesis.log -p 'read_verilog -sv -Ihardware $(CONSOLE_RTL) $(CPU); synth_gowin -nowidelut -top tangnano9k_console -json $@; check -assert'

build/console.pnr.json: build/console.json hardware/tangnano9k-console.cst hardware/tangnano9k-video.sdc Makefile
	$(NEXTPNR) --json $< --write $@ --device GW1NR-LV9QN88PC6/I5 \
		--vopt family=GW1N-9C --vopt cst=hardware/tangnano9k-console.cst \
		--sdc hardware/tangnano9k-video.sdc --freq 27 --seed 1 \
		--report build/console-timing.json --log build/console-place-route.log

build/console.fs: build/console.pnr.json scripts/check_timing.py Makefile build/images/SMOKE.BIN build/images/LUNAR.BIN
	$(PYTHON) scripts/check_timing.py build/console-timing.json --min-mhz 25.2 \
		--expect-mhz 27 --expect-mhz 25.2
	@if [ -f $@ ]; then mkdir -p build/bitstream-backup; \
		cp -p $@ build/bitstream-backup/$$(shasum -a 256 $@ | cut -d ' ' -f 1).fs; fi
	$(PACK) -d GW1N-9C -o $@ $<
	shasum -a 256 $@ > build/console.fs.sha256
	shasum -a 256 Makefile scripts/*.py tests/*.sv tests/*.py tests/*.vlt \
		$(CONSOLE_RTL) $(CPU) third_party/font8x8/font8x8_basic.h \
		firmware/* hardware/*.vh hardware/tangnano9k-console.cst hardware/tangnano9k-video.sdc \
		build/boot.elf build/boot.bin build/smoke.elf build/smoke.bin \
		build/images/SMOKE.BIN build/images/LUNAR.BIN build/lunar.elf build/font.hex build/hud-font.hex \
		build/lander.hex build/earth.hex build/memorial.hex build/memorial-text.hex photos/* > build/console-sources.sha256

console-bitstream: test test-boot lint console-lint images build/console.fs

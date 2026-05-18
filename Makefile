SRC_HEADER = src/header.sh
SRC_ENGINE = src/engine.tcl
SRC_CLI    = src/cli.tcl
SRC_GUI    = src/gui.tcl
SRC_MAIN   = src/main.tcl
OUT        = sparkwyrd.tcl

# Lines stripped when merging individual source files:
# shebang lines, source-engine calls, script_dir declarations
STRIP = grep -v '^\#!/\|^source.*engine\.tcl\|^set script_dir'

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRC_HEADER) $(SRC_ENGINE) $(SRC_CLI) $(SRC_GUI) $(SRC_MAIN)
	@cat $(SRC_HEADER)                                                        > $(OUT)
	@printf '\nset script_dir [file normalize [file dirname [info script]]]\n' >> $(OUT)
	@printf 'set ::sparkwyrd_combined 1\n\n'                                  >> $(OUT)
	@printf '# === engine ===\n' >> $(OUT) && $(STRIP) $(SRC_ENGINE)          >> $(OUT)
	@printf '\n# === cli ===\n'  >> $(OUT) && $(STRIP) $(SRC_CLI)             >> $(OUT)
	@printf '\n# === gui ===\n'  >> $(OUT) && $(STRIP) $(SRC_GUI)             >> $(OUT)
	@printf '\n# === main ===\n' >> $(OUT) && cat $(SRC_MAIN)                 >> $(OUT)
	@chmod +x $(OUT)
	@echo "Built $(OUT)"

clean:
	rm -f $(OUT)

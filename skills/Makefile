.PHONY: list install install-global

SRC_DIR := src
GLOBAL_SKILLS_DIR := $(HOME)/.claude/skills

list:
	@ls -1 "$(SRC_DIR)" | sed 's/\/$$//' || true

# Install skills into target repo's .cursor/skills/
# Usage: make -C skills install TARGET=/path/to/repo
install:
	@if [ -z "$(TARGET)" ]; then echo "TARGET is required. e.g. make -C skills install TARGET=.."; exit 2; fi
	@mkdir -p "$(TARGET)/.cursor/skills"
	@for d in "$(SRC_DIR)"/*; do \
		if [ -d "$$d" ]; then \
			name="$$(basename "$$d")"; \
			mkdir -p "$(TARGET)/.cursor/skills/$$name"; \
			cp -rf "$$d/." "$(TARGET)/.cursor/skills/$$name/"; \
			echo "installed: $$name"; \
		fi; \
	done

# Install all skills into ~/.claude/skills/ for global Claude Code use
# Usage: make -C skills install-global
install-global:
	@mkdir -p "$(GLOBAL_SKILLS_DIR)"
	@for d in "$(SRC_DIR)"/*; do \
		if [ -d "$$d" ]; then \
			name="$$(basename "$$d")"; \
			mkdir -p "$(GLOBAL_SKILLS_DIR)/$$name"; \
			cp -rf "$$d/." "$(GLOBAL_SKILLS_DIR)/$$name/"; \
			echo "installed globally: $$name"; \
		fi; \
	done


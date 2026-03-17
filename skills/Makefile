.PHONY: list install

SRC_DIR := src

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
			cp -f "$$d/SKILL.md" "$(TARGET)/.cursor/skills/$$name/SKILL.md"; \
			echo "installed: $$name"; \
		fi; \
	done


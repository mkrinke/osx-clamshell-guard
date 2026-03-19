BINARY     = osx-clamshell-guard
PREFIX    ?= /usr/local
PLIST_NAME = com.osx-clamshell-guard.plist
DAEMON_DIR = /Library/LaunchDaemons
LOG_DIR    = /var/log/osx-clamshell-guard
LABEL      = com.osx-clamshell-guard

.PHONY: build install install-service uninstall load unload restart status log clean

build:
	swiftc -O -o $(BINARY) Sources/main.swift

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BINARY) $(PREFIX)/bin/
	install -d $(LOG_DIR)

install-service: install
	sed 's|__PREFIX__|$(PREFIX)|g' $(PLIST_NAME) \
		| tee $(DAEMON_DIR)/$(PLIST_NAME) > /dev/null
	launchctl bootstrap system $(DAEMON_DIR)/$(PLIST_NAME)
	@echo ""
	@echo "$(BINARY) installed and running"
	@echo "Logs: $(LOG_DIR)/$(BINARY).log"

uninstall:
	-sudo launchctl bootout system/$(LABEL) 2>/dev/null
	-sudo rm -f $(PREFIX)/bin/$(BINARY)
	-sudo rm -f $(DAEMON_DIR)/$(PLIST_NAME)
	@echo "$(BINARY) uninstalled"

load:
	sudo launchctl bootstrap system $(DAEMON_DIR)/$(PLIST_NAME)

unload:
	sudo launchctl bootout system/$(LABEL)

restart: unload load

status:
	@sudo launchctl list | grep osx-clamshell-guard || echo "Not running"
	@echo ""
	@pmset -g assertions | grep -i clamshell || true

log:
	tail -f $(LOG_DIR)/$(BINARY).log

clean:
	rm -f $(BINARY)

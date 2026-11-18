# Установка WOL Gateway на OpenWrt или в staging-каталог.
PREFIX ?=
DESTDIR ?=

BIN_DIR = $(DESTDIR)/usr/bin
LIB_DIR = $(DESTDIR)/usr/lib/wol-gateway
INIT_DIR = $(DESTDIR)/etc/init.d
ETC_DIR = $(DESTDIR)/etc

.PHONY: install uninstall

install:
	install -d -m 0755 "$(BIN_DIR)" "$(LIB_DIR)" "$(INIT_DIR)"
	install -m 0755 files/usr/bin/wol-gateway "$(BIN_DIR)/wol-gateway"
	install -m 0644 files/usr/lib/wol-gateway/config.sh "$(LIB_DIR)/config.sh"
	install -m 0644 files/usr/lib/wol-gateway/telegram.sh "$(LIB_DIR)/telegram.sh"
	install -m 0644 files/usr/lib/wol-gateway/actions.sh "$(LIB_DIR)/actions.sh"
	install -m 0755 files/etc/init.d/wol-gateway "$(INIT_DIR)/wol-gateway"
	@if [ ! -f "$(ETC_DIR)/wol-gateway.env.example" ]; then \
		install -d -m 0755 "$(ETC_DIR)"; \
		install -m 0600 files/etc/wol-gateway.env.example "$(ETC_DIR)/wol-gateway.env.example"; \
	fi

uninstall:
	rm -f "$(BIN_DIR)/wol-gateway"
	rm -f "$(INIT_DIR)/wol-gateway"
	rm -rf "$(LIB_DIR)"

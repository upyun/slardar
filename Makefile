##############################################################################
# Project Slardar top level Makefile for installation. Requires GNU Make.
#
# Suitable for POSIX platforms (Linux, *BSD, OSX etc.)
#
# Copyright (C) 2015 - 2016, UPYUN Inc.
##############################################################################

include util/ver.cfg

ROOTDIR= $(shell pwd)

ifeq (dev,$(firstword $(MAKECMDGOALS)))
PREFIX= $(ROOTDIR)
DEV= 1
endif

ifndef PREFIX
PREFIX= /usr/local/slardar
endif

ifeq ($(shell uname -s), Darwin)
PLAT=macosx
else
PLAT=linux
endif

export LUAJIT_LIB= $(PREFIX)/luajit/lib
export LUAJIT_INC= $(PREFIX)/luajit/include/luajit-2.1

##############################################################################

RM= rm -f
CP= cp -f
MKDIR= mkdir -p
RMDIR= rmdir 2>/dev/null
INSTALL_F= install -m 0644
UNINSTALL= $(RM)

##############################################################################

NGINX_DIR= deps/nginx-$(V_NGINX)
default all: cjson cmsgpack luasocket
	@echo "==== Building Nginx $(V_NGINX) ===="
	cd $(NGINX_DIR) && $(MAKE) -j2
	@echo "==== Successfully build Nginx $(V_NGINX) ===="

INSTALL_LIBDIR=$(PREFIX)/nginx/app/lib/
configure: deps luajit
	@echo "==== Configuring Nginx $(V_NGINX) ===="
	cd $(NGINX_DIR) && ./configure \
		--with-pcre=$(ROOTDIR)/deps/pcre-$(V_PCRE) \
		--with-ld-opt="-Wl,-rpath,$(LUAJIT_LIB),-rpath,$(INSTALL_LIBDIR)" \
		--with-http_stub_status_module \
		--with-stream \
		--add-module=$(ROOTDIR)/deps/stream-lua-nginx-module-$(V_STREAM_LUA_NGX_MODULE) \
		--add-module=$(ROOTDIR)/deps/lua-nginx-module-$(V_NGX_LUA_MODULE) \
		--prefix=$(PREFIX)/nginx
	@echo "==== Successfully configure Nginx $(V_NGINX) ===="

INSTALL_SRCDIR=$(PREFIX)/nginx/app/src/
INSTALL_ETCDIR=$(PREFIX)/nginx/app/etc/
INSTALL_DIRS=$(INSTALL_SRCDIR)/modules \
			 $(INSTALL_SRCDIR)/script \
			 $(INSTALL_LIBDIR)/ngx \
			 $(INSTALL_LIBDIR)/resty \
			 $(INSTALL_LIBDIR)/resty/core \
			 $(INSTALL_LIBDIR)/resty/checkups \
			 $(INSTALL_ETCDIR)

install: install-cjson install-cmsgpack
	$(MKDIR) $(INSTALL_DIRS) $(PREFIX)/nginx/conf/slardar
	@echo "==== Installing Slardar $(V_SLARDAR) to $(PREFIX) ===="
	cd $(NGINX_DIR) && $(MAKE) install
ifndef DEV
	$(INSTALL_F) nginx/app/lib/resty/*.lua $(INSTALL_LIBDIR)/resty
	$(INSTALL_F) nginx/app/lib/ngx/*.lua $(INSTALL_LIBDIR)/ngx
	$(INSTALL_F) nginx/app/lib/resty/core/*.lua $(INSTALL_LIBDIR)/resty/core
	$(INSTALL_F) nginx/app/lib/resty/checkups/*.lua $(INSTALL_LIBDIR)/resty/checkups
	$(INSTALL_F) nginx/app/src/*.lua $(INSTALL_SRCDIR)
	$(INSTALL_F) nginx/app/etc/*.lua $(INSTALL_ETCDIR)
	$(INSTALL_F) nginx/app/src/modules/*.lua $(INSTALL_SRCDIR)/modules
	$(INSTALL_F) nginx/conf/*.conf $(PREFIX)/nginx/conf
	$(INSTALL_F) nginx/conf/slardar/*.conf $(PREFIX)/nginx/conf/slardar
endif
	@echo "==== Successfully installed Slardar $(V_SLARDAR) to $(PREFIX) ===="

dev: configure all install

##############################################################################

deps:
	./util/deps

LUAJIT_DIR= deps/luajit2-$(V_LUAJIT)
luajit:
	cd $(LUAJIT_DIR) && $(MAKE) PREFIX=$(PREFIX)/luajit && $(MAKE) install PREFIX=$(PREFIX)/luajit


LUA_CJSON_DIR= deps/lua-cjson-$(V_LUA_CJSON)
cjson:
	@echo "==== Building Lua CJSON $(V_LUA_CJSON) ===="
ifeq ($(shell uname -s), Darwin)
	cd $(LUA_CJSON_DIR) && $(MAKE) LUA_INCLUDE_DIR=$(LUAJIT_INC) "CJSON_LDFLAGS+=-undefined dynamic_lookup"
else
	cd $(LUA_CJSON_DIR) && $(MAKE) LUA_INCLUDE_DIR=$(LUAJIT_INC)
endif
	@echo "==== Successfully build Lua CJSON $(V_LUA_CJSON) ===="

install-cjson:
	$(MKDIR) $(INSTALL_LIBDIR)
	$(INSTALL_F) $(LUA_CJSON_DIR)/*.so $(INSTALL_LIBDIR)


LUA_CMSGPACK_DIR= deps/lua-cmsgpack-$(V_CMSGPACK)
cmsgpack:
	@echo "==== Building Lua cmsgpack ===="
ifeq ($(shell uname -s), Darwin)
	cd $(LUA_CMSGPACK_DIR) && $(MAKE) LUA_INCLUDE_DIR=$(LUAJIT_INC) "CMSGPACK_LDFLAGS+=-undefined dynamic_lookup"
else
	cd $(LUA_CMSGPACK_DIR) && $(MAKE) LUA_INCLUDE_DIR=$(LUAJIT_INC)
endif
	@echo "==== Successfully build Lua cmsgpack ===="

install-cmsgpack:
	$(MKDIR) $(INSTALL_LIBDIR)
	$(INSTALL_F) $(LUA_CMSGPACK_DIR)/*.so $(INSTALL_LIBDIR)


LUASOCKET_DIR = deps/luasocket-$(V_LUASOCKET)
luasocket: luajit
	cd $(LUASOCKET_DIR);make LUAINC=$(LUAJIT_INC) PLAT=$(PLAT)
	cd $(LUASOCKET_DIR);make LUAINC=$(LUAJIT_INC) PLAT=$(PLAT) prefix=$(PREFIX)/luajit  install


clean:
	cd $(LUAJIT_DIR) && $(MAKE) clean
	cd $(NGINX_DIR) && $(MAKE) clean
	cd $(LUA_CJSON_DIR) && $(MAKE) clean
	cd $(LUA_CMSGPACK_DIR) && $(MAKE) clean
	@rm -rf $(ROOTDIR)/luajit
	@rm -rf $(ROOTDIR)/nginx/app/lib/*.so
	@rm -rf $(ROOTDIR)/nginx/sbin/nginx

.PHONY: deps luajit cjson cmsgpack clean luasocket

##############################################################################

start:
	./nginx/sbin/nginx
	@echo "NGINX start"

stop:
	-kill -QUIT `cat ./nginx/logs/nginx.pid`
	@echo "NGINX stop"

reload:
	-kill -HUP `cat ./nginx/logs/nginx.pid`
	@echo "NGINX reload"

test:
	util/lua-releng
	python ./util/ytest

##############################################################################

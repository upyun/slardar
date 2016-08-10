# coding: utf-8

import re
import os
import hashlib

SLARDAR_DIR = os.getcwd()
IMG_DIR = os.path.join(SLARDAR_DIR, 'tests/img')

# env for ytest, run cases in random order
RANDOM = True
STOP_SERVER = '''ps aux | grep nginx | grep -v grep |
              grep -v tail | grep -v vim | awk \'{print $2}\' |
              xargs kill -9 > /dev/null 2>&1'''
PRE_START_SERVER = '''mkdir -p tests/servroot &&
               cp -r nginx/conf tests/servroot &&
               cp tests/test.conf tests/servroot/conf/slardar &&
               cp -r nginx/app tests/servroot &&
               cp -r luajit tests/luajit &&
               mkdir -p tests/servroot/logs'''
START_SERVER = 'nginx/sbin/nginx -p tests/servroot 1> /dev/null'
RELOAD_SERVER = 'nginx/sbin/nginx -s reload -p tests/servroot 1> /dev/null'
LOG_PATH = 'tests/servroot/logs/error.log'
CONFIG_PATH = 'tests/servroot/app/etc/config.lua'

TIMEOUT = 15

with open("%s/nginx/app/src/init.lua" % SLARDAR_DIR) as f:
    m = re.findall('slardar.global.version = "(\d+.\d+).\d+"', f.read())
    SLARDAR_VERSION = m[0]


class _errno(object):
    ERRNO_FILE = '%s/nginx/app/src/modules/errno.lua' % SLARDAR_DIR

    def __init__(self):
        self.error_dict = dict()

        with open(self.ERRNO_FILE) as f:
            data = f.read()
            errors = re.findall('([A-Z_0-9]+)\s+=\s+{(\d+),\s+"(.+?)"', data)
            for const, code, _ in errors:
                self.error_dict[const] = int(code)

    def __getattr__(self, name):
        return self.error_dict.get(name)

errno = _errno()


def md5(s):
    return hashlib.md5(s).hexdigest()


def body_md5(s, unused):
    return md5(s)


def get_test_file_content(fname):
    with open(os.path.join(IMG_DIR, fname)) as f:
        data = f.read()
    return data

Slardar
=======

Updating your upstream list and run lua scripts without reloading Nginx.

Table of Contents
=================

* [Description](#description)
* [Installation](#installation)
	* [Install From Source](#install-from-source)
	* [Build Docker Image](#build-docker-image)
* [Configuration](#configuration)
	* [Lua Configuration](#lua-configuration)
	* [Consul Configuration](#consul-configuration)
	* [Nginx Configuration](#nginx-configuration)
* [Interface](#interface)
	* [Get Slardar Status](#get-slardar-status)
	* [Get Scripts Status](#get-scripts-status)
	* [Update Upstream](#update-upstream)
	* [Delete Upstream](#delete-upstream)
	* [Post Lua Scripts or Modules](#post-lua-scripts-or-modules)
	* [Load Lua Scripts or Modules](#load-lua-scripts-or-modules)
* [Example](#example)
* [Run Test](#run-test)
* [Contribution](#contribution)
* [Copyright & License](#copyright--license)

Description
===========

Slardar is a HTTP load balancer based on [Nginx](http://nginx.org/) and [lua-nginx-module](https://github.com/openresty/lua-nginx-module), with which you can update your upstream list and run lua scripts without reloading Nginx.

This bundle is maintained by UPYUN(又拍云) Inc.

Because most of the nginx modules are developed by the bundle maintainers, it can ensure
that all these modules are played well together.

The bundled software components are copyrighted by the respective copyright holders.



Installation
============

Install from source
-------------------


**1. Clone the repository**


```
git clone https://github.com/upyun/slardar.git
```

**2. Set installation directory (optional)**

By default, Slardar will be installed to `/usr/local/slardar`, and you should ensure that you have write permission to the directory.

If you want to change to another location, you should export the `PREFIX` environment variable to the path you want to install. 

```
export PREFIX=/path/to/your/dir
```

**3. Configure**

```
cd slardar
make configure
```


**4. Build and Install**

```
make
make install
```

**5. Run**

```
/usr/local/slardar/nginx/sbin/nginx
```

or you have changed installation directory in step 2:

```
$PREFIX/nginx/sbin/nginx
```

[Back to TOC](#table-of-contents)


Build Docker Image
------------------

**1. Clone the repository**

```
git clone https://github.com/upyun/slardar.git
```

**2. Build docker image**

```
cd slardar
docker build -t slardar .
```

**3. Run**

```
docker run -d -P --name slardar slardar
```



[Back to TOC](#table-of-contents)


Configuration
=============

Lua configuration
-----------------

Contiguration file is in `lua` format and located at `/usr/local/slardar/nginx/app/etc/config.lua` or `$PREFIX/nginx/app/etc/config.lua` if you changed your installation location.

Example configuration and the comments are listed as follows.

```
local _M = {}

_M.global = {

    -- checkups send heartbeats to backend servers every 5s.
    checkup_timer_interval = 5,
    
    -- checkups timer key will expire in every 60s.
    -- In most cases, you don't need to change this value.
    checkup_timer_overtime = 60,
    
    -- checkups will sent heartbeat to servers by default.
    default_heartbeat_enable = true,

	-- create upstream syncer for each worker.
	-- If set to false, dynamic upstream will not work properly.
	-- This switch is used for compatibility purpose only in checkups,
	-- don't change this in slardar.
    checkup_shd_sync_enable = true,
    
    -- sync upstream list from shared memory every 1s
    shd_config_timer_interval = 1,
    
    -- the key prefix for upstreams in shared memory
    shd_config_prefix = "shd_v1",
}

_M.consul = {
	-- connect to consul will timeout in 5s.
    timeout = 5,

    -- disable checkups heartbeat to consul.
    enable = false,

	-- consul k/v prefix.
	-- Slardar will read upstream list from config/slardar/upstreams.
	-- For more information, please refer to 'Consul configuration'. 
    config_key_prefix = "config/slardar/",
    
    -- positive cache ttl(in seconds) for dynamic configurations from consul.
    config_positive_ttl = 10,
    
    -- negative cache ttl(in seconds) for dynamic configurations from consul.
    config_negative_ttl = 5,
    
    -- do not cache dynamic configurations from consul.
    config_cache_enable = true,

    cluster = {
        {
            servers = {
                -- change these to your own consul http addresses
                { host = "10.0.5.108", port = 8500 },
                { host = "10.0.5.109", port = 8500 },
            },
        },
    },
}

return _M
```

Consul configuration
--------------------

Slardar will read persisted configurations, upstream list and lua code from consul on startup. Consul configuration can be customized by setting k/v with the prefix `config_key_prefix`(e.g.`config/slardar/`) configured in `config.lua`. You should ensure that all values behind `config_key_prefix` are in valid `json` format.

An example Consul keys and their corresponding values are listed as follows,

| consul k/v key 		| value     |
|----------------------|-----------|
| lua/modules.abc 		| `local f = {version=10} return f` |
| lua/script.test  		| `local f = require("modules.abc") print(f.version)` |
| upstreams/node-dev.example   | `{"enable": true, "servers": [{"host": "127.0.0.1","port": 8001,"weight": 1,"max_fails": 6,"fail_timeout": 30}]}` |
| myargs 				| `{"arg0": 0,"arg1": 1}` |

For the above example, Slardar will load `modules.abc`, `script.test` as lua code and `node-dev.example` as upstream on startup.

You can set `"enable": false`(default is `true`) in your upstream configuration to disable periodical heartbeats to servers by checkups.

When Slardar is running, you can use `slardar.myargs.arg0` to get `arg0` and `slardar.myargs.arg1` to get `arg1`. The config will be cached for `config_positive_ttl` seconds. That is to say, when you change the value of `myargs` in consul, it will take effect in `config_positive_ttl` seconds.

Differs to configurations like `myargs`, keys behind `lua` and `upstreams` will not be cached and you can only update them by Slardar's [HTTP interfaces](#interface).

If you don't need any preload scripts or upstreams, just leave nothing behind `config_key_prefix` or an empty value.


Nginx configuration
-------------------

Slardar is 100% compatible with nginx, so you can change nginx configuration files in the same way you do for Nginx.

Configuration files for Nginx are located at `/usr/local/slardar/nginx/conf` or `$PREFIX/nginx/conf` if you changed your installation location.

[Back to TOC](#table-of-contents)


Interface
=========

Get Slardar status
------------------

```
GET 127.0.0.1:1995/status
```

Slardar will return its status in json format.

```
{
	-- checkups heartbeat timer is alive.
	"checkup_timer_alive": true,
	
	-- last heartbeat time
	"last_check_time": "2016-08-12 13:09:40",
	
	-- slardar version
	"slardar_version": "1.0.0",
	
	-- start or reload time.
	"start_time": "2016-08-12 13:09:40",
	
	-- lua config file version, you can set 'conf_hash = "your-version"' in your lua config file.
	"conf_hash": null,
	
	-- every time you update upstream, this value will increase.
	"shd_config_version": 0,
	
	-- status for consul cluster
	"cls:consul": [
		[
			{
				"server": "consul:10.0.5.108:8500",
				"weight": 1,
				"status": "unchecked"
			}
		]
	],
	
	-- status for node-dev cluster
	"cls:node-dev": [
		[
			{
				"server": "node-dev:10.0.5.108:8001",
				"weight": 1,
				"fail_timeout": 30,
				"status": "ok",
				"max_fails": 6
			}
		]
	]
}
```

Get scripts status
---------------------------

```
GET 127.0.0.1:1995/lua
```

Slardar will return loaded lua scripts and modules in json format.

```
{
	-- every time you update lua scripts, this value will increase.
	"version": 0,
	"modules": [
		{
			-- module load time
			"time": "2016-08-12 13:09:40",
			
			-- md5 value of module file
			"version": "aed4a968ef14f8db732e3602c34dc37a",
			
			-- module name
			"name": "modules.test"
		},
		{
			"time": "2016-08-12 13:09:40",
			"version": "302f9bf40fcd3734cab120b97f18edf3",
			"name": "script.test"
		}
	]
}
```

Update upstream
---------------

```
POST 127.0.0.1:1995/upstream/name
```

The request body is your new upstream list in json format. For example,

```
curl 127.0.0.1:1995/upstream/node-dev.example.com -d \
{"servers":[{"host":"192.168.1.1", "port": 8080}, {"host":"192.168.1.2", "port": 8080}]}
```

The example above will add two servers into upstream named `node-dev.example.com`.

Delete upstream
---------------

```
DELETE 127.0.0.1:1995/upstream/name
```

For example,

```
curl -XDELETE 127.0.0.1:1995/upstream/node-dev.example.com
```

The example above will delete the upstream named `node-dev.example.com`.

Post lua scripts or modules
---------------------------

```
POST 127.0.0.1:1995/lua/scripts.name
```

or post a lua module,

```
POST 127.0.0.1:1995/lua/modules.name
```

The request body is the lua code of your script or module. For example,

```
curl 127.0.0.1:1995/lua/scripts.test -d 'return slardar.exit(errno.EXIT_TRY_CODE)'
curl 127.0.0.1:1995/lua/modules.test -d 'local f = {version=10} return f'
```

Load lua scripts or modules
---------------------------

```
PUT 127.0.0.1:1995/lua/scripts.name
```
or load a lua module,

```
PUT 127.0.0.1:1995/lua/modules.name
```
Before loading lua, you must [post](post-lua-scripts-or-modules) the lua script or module to Slardar.

For example,

```
curl -XPUT 127.0.0.1:1995/lua/scripts.test
curl -XPUT 127.0.0.1:1995/lua/modules.test
```



[Back to TOC](#table-of-contents)


Example
=======

Get from upstream which does not exist will result in 502. 

```
$ curl 127.0.0.1:8080/ -H "Host: node-dev.example.com"
<html>
<head><title>502 Bad Gateway</title></head>
<body bgcolor="white">
<center><h1>502 Bad Gateway</h1></center>
<hr><center>slardar/1.0</center>
</body>
</html>
```

Add one server to `node-dev.example.com`

```
$ curl 127.0.0.1:1995/upstream/node-dev.example.com -d '{"servers":[{"host":"127.0.0.1", "port": 4000}]}'
{"status":200}
```

Now, we can get the correct result.

```
$ curl 127.0.0.1:8080/ -H "Host: node-dev.example.com"
hello world
```

Load a loa script

```
$ curl 127.0.0.1:1995/lua/script.node-dev.example.com -d 'if ngx.get_method() == "DELETE" then return ngx.exit(403) end'
"ok"
$ curl -XPUT 127.0.0.1:1995/lua/script.test
```

The script is taking effect.

```
$ curl -XDELETE 127.0.0.1:8080/ -H "Host: node-dev.example.com"
<html>
<head><title>403 Forbidden</title></head>
<body bgcolor="white">
<center><h1>403 Forbidden</h1></center>
<hr><center>slardar/1.0</center>
</body>
</html>
```

[Back to TOC](#table-of-contents)


Run Test
========

This bundle contains only tests for Slardar, the bundled components are tested in their own project.

You can run `make test` to run tests for Slardar.


[Back to TOC](#table-of-contents)


Contribution
============================

You're very welcome to report issues on [GitHub](https://github.com/upyun/slardar/issues).

PRs are more than welcome. Just fork, create a feature branch, and open a PR. We love PRs. :)

[Back to TOC](#table-of-contents)


Copyright & License
===================

The bundle itself is licensed under the 2-clause BSD license.

Copyright (c) 2016, UPYUN(又拍云) Inc.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

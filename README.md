Name
====

lua-resty-cache-expire Expire nginx cache based on regular expressions

Status
======

This library is considered experimental and still under active development.

The API is still in flux and may change without notice.

Description
===========

By default this module requires cache key to be separated by \x01 ()

Synopsis
========

``lua`
    # nginx.conf:

    location / {
        proxy_cache_key  $host$uri$is_args$args;
        proxy_pass       http://upstream;
    }

    location /expire_jpegs_on_127.0.0.1 {
        content_by_lua_block {
            local cache_expire = require "cache_expire"
            cache_expire('/path/to/cache', { [[^127\.0\.0\.1$]], [[\.jpe?g$]] }
        }
    }

Author
======

Bjørnar Ness <bjornar.ness@gmail.com>

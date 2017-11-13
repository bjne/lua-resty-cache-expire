-- Copyright (C) by Bjørnar Ness (bjne@github)

local _M = { _VERSION = 0.1 }

local ffi = require "ffi"

local C = ffi.C
local cast = ffi.cast
local ffi_errno = ffi.errno
local ffi_string = ffi.string

local len = string.len
local sub = string.sub

local wrap = coroutine.wrap
local yield = coroutine.yield

local insert = table.insert

local rxmatch = ngx.re.match
local rxgmatch = ngx.re.gmatch

local open = io.open

ffi.cdef[[
typedef __int64         time_t;
typedef uintptr_t       ngx_uint_t;
typedef unsigned short  u_short;
typedef unsigned char   u_char;

static const int NGX_HTTP_CACHE_ETAG_LEN = 128;
static const int NGX_HTTP_CACHE_VARY_LEN = 128;
static const int NGX_HTTP_CACHE_KEY_LEN  = 16;

typedef struct {
        ngx_uint_t      version;
        time_t          valid_sec;
        time_t          updating_sec;
        time_t          error_sec;
        time_t          last_modified;
        time_t          date;
        uint32_t        crc32;
        u_short         valid_msec;
        u_short         header_start;
        u_short         body_start;
        u_char          etag_len;
        u_char          etag[NGX_HTTP_CACHE_ETAG_LEN];
        u_char          vary_len;
        u_char          vary[NGX_HTTP_CACHE_VARY_LEN];
        u_char          variant[NGX_HTTP_CACHE_KEY_LEN];
} ngx_http_file_cache_header_t;
]]

ffi.cdef[[
typedef unsigned long       ino_t;
typedef long                off_t;
typedef struct __dirstream  DIR;

typedef struct {
        ino_t           ino;       /* inode number  */
        off_t           off;       /* not an offset */
        unsigned short  reclen;    /* record length */
        unsigned char   type;      /* type of file  */
        char            name[256]; /* filename      */
} dirent_t;

char *strerror(int errnum);
DIR *opendir(const char *name);
dirent_t *readdir(DIR *dirp);
int closedir(DIR *dirp);
]]

local DT_DIR = 4
local DT_REG = 8

local cache_header_version = 5
local cache_header_size = ffi.sizeof("ngx_http_file_cache_header_t")

local function cache_key(cache_file)
    cache_file = open(cache_file, 'r')
    if cache_file then
        local cache_header = cache_file:read(cache_header_size)
        if cache_header then
            cache_header = cast("ngx_http_file_cache_header_t *", cache_header)
            local hdrver = tonumber(cache_header.version)
            if cache_header and hdrver == cache_header_version then
                if cache_file:read(1 + 3 + 1 + 1) == "\nKEY: " then
                    return cache_file:read('*l'), cache_header, cache_file:close()
                end
            end
        end
        cache_file:close()
    end
end

local function recurse_cache(cache_path)
    local function _recurse(path)
        local dirp = C.opendir(path)
        if dirp == nil then
            return ngx.log(ngx.ERR, ffi_string(C.strerror(ffi_errno())))
        end

        while true do
            local dirent = C.readdir(dirp)
            if dirent == nil then
                C.closedir(dirp)
                dirp = nil
                return
            end

            local filename = ffi_string(dirent.name)
            local nextpath = path .. '/' ..filename

            if dirent.type == DT_DIR then
                if filename ~= '.' and filename ~= '..' then
                    _recurse(nextpath)
                end
            elseif dirent.type == DT_REG and len(filename) == 32 then
                local cache_key, cache_header = cache_key(nextpath)
                if cache_key then
                    yield(cache_key, cache_header, nextpath)
                end
            end
        end
    end

    return wrap(function() return _recurse(cache_path) end)
end

local function expire(cache_file, cache_header)
    cache_header.valid_sec = 0
    cache_file = open(cache_file, 'r+b')
    if cache_file then
        cache_file:write(ffi.string(cache_header, cache_header_size))
        cache_file:close()
    end
end

_M.expire = function(cache_path, regex_t, return_result)
    return_result = return_result and {}
    for cache_key, cache_header, cache_file in recurse_cache(cache_path) do
        if tonumber(cache_header.valid_sec) > ngx.time() then
            local regex_it = rxgmatch(cache_key, [[([^\x01]+)]], 'jo')
            if regex_it then
                local match = true
                for i=1,#regex_t do
                    local value = regex_it()
                    if not value or not rxmatch(value[0], regex_t[i], 'j') then
                        match = false
                        break
                    end
                end

                if match then
                    if return_result then
                        insert(return_result, cache_key)
                    end

                    expire(cache_file, cache_header)
                end
            end
        end
    end

    return return_result
end

return _M

-- vim: ts=4 sw=4 et ai

local redis = require "resty.redis"
local cjson_decode = require("cjson").decode
local cjson_encode = require("cjson").encode

local _M = {}

local function json_decode(json)
    if json then
        local status, res = pcall(cjson_decode, json)
        if status then
        return res
        end
    end
end

local function json_encode(table)
    if table then
        local status, res = pcall(cjson_encode, table)
        if status then
        return res
        end
    end
end

function _M:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function _M:set_config(config)
    self.config = config or {}
end

function _M:connect()
    self.red = redis:new()
    self.red:set_timeout(self.config.redis.timeout)
    local ok, err = self.red:connect(self.config.redis.host, self.config.redis.port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to Redis: ", err)
        return false
    end
    local pass = self.config.redis.password
    if pass ~= nil and string.len(pass) > 0 then
        local ok, err = self.red:auth(pass)
        if not ok then
            ngx.log(ngx.ERR, "failed to authenticate: ", err)
            return false
        end
    end
    local db = self.config.redis.database
    if db > 0 then
        local ok, err = self.red:select(db)
        if not ok then
            ngx.log(ngx.ERR, "failed to select database: ", err)
            return false
        end
    end
    return true
end

function _M:close()
    local ok, err = self.red:set_keepalive(10000, 1000)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        return nil, err
    end
    return self.red
end

function _M:set(key, value, expire_time)
    ngx.timer.at(0, function(premature)
        local connected = self:connect()
        if not connected then
            return
        end
        local ok, err = self.red:set(key, json_encode(value))
        if not ok then
            ngx.log(ngx.ERR, "failed to set cache: ", err)
            return
        end
        self.red:expire(key, expire_time)
        self:close()
    end)
end

function _M:get(key)
    local connected = self:connect()
    if not connected then
        return nil
    end
    local cached_value, err = self.red:get(key)
    if err then
        ngx.log(ngx.ERR, "failed to get cache: ", err)
        return nil, err
    end
    self:close()
    return json_decode(cached_value)
end

return _M

-- Order --

local hash_types, TTYPES = {} do
    local order = {
        false,
        true,
        "float",
        "integer",
        "string",
        "table",
        "function",
        "thread",
        "userdata"
    }
    TTYPES = #order
    for k , v in pairs(order) do hash_types[v] = k end
end


local topointer if _VERSION >= "Lua 5.4" then
    function topointer(x) return ("%p"):format(x) end
else
    function topointer(x)
        local str if type(x) == "table" then
            local restore = getmetatable(x)
            setmetatable(x, nil)
            str = tostring(x)
            setmetatable(x, restore)
        else
            str = tostring(x)
        end
        local _, addressstarts = str:find(": ")
        return str:sub(addressstarts + 1)
    end
end


local mts = setmetatable({}, {__mode = 'k'})
local available = {} for i = 11, 254 do available[i] = i end
local reclaimer_t = {__gc = function(t) table.insert(available, t[1]) end}

local function reclaimer(i)
    return setmetatable({i}, reclaimer_t)
end


local function hash(value)
	local tt = math.type(value) or type(value)
	if value == nil then
		return "\0"
	elseif tt == "boolean" then
		return  string.char(hash_types[value])
	elseif tt == "float" then
		return ("Bn"):pack(3, value)
	elseif tt == "integer" then
		return ("Bj"):pack(4, value)
    elseif tt == "string" then
        return '\5' .. value
	else
        local mt = getmetatable(value)
        if mt and mt.__map_hash then
            if not mts[mt] then
                if #available == 0 then return error("No tag available to hash custom datatype.") end
                mts[mt] = reclaimer(table.remove(available))
            end
            return string.char(mts[mt][1]).. mt.__map_hash(value)
        end
		local p = tonumber(topointer(value), 16)
		return ("BJ"):pack(hash_types[tt], p)
	end
end


local LT,EQ,GT = 0, 1, 2

local function compare(A, B)
    local hA, hB = hash(A), hash(B)
    if hA < hB then return LT
    elseif hA == hB then return EQ
    else return GT
    end
end

-- Tags --

local Tag = {}
local Data = {}

local module

-- Common Methods --

local function common_methods(Tip, Bin, lookup)

    local function null(x) return x == Tip end

    local function size(x)
        return x == Tip and 0 or x[Data][1]
    end

    local function missing(k, object)
        local _, result = lookup(k, object)
        return not not result
    end

    return null, size, missing
end


-- Maps --
do

local map_t = {__name = "map"}


local Tip = setmetatable({[Tag] = "map.Tip"}, map_t)


local function Bin(Size, k, v, Left, Right)
    return setmetatable({[Data] = {Size, k, v, Left, Right}, [Tag] = "map.Bin"}, map_t)
end


-- Query --

local function lookup(k, map)
	if map == Tip then return nil, true
	else
		local _, kx, x, l, r = table.unpack(map[Data], 1, 5)
        local cmp = compare(k, kx)
		if cmp == LT then
            return lookup(k, l)
		elseif cmp == GT then
            return lookup(k, r)
		else
            return x
		end
	end
end

-- Common Methods --

local null, size, missing = common_methods(Tip, Bin, lookup)


-- Balancing --

local delta,ratio = 4, 2

local rotateL, rotateR, singleL, singleR, doubleL, doubleR


local function bin(k, v, l, r) return Bin(size(l) + size(r) + 1, k, v, l, r) end


local function balance(k, v, l, r)
	local sizeL, sizeR = size(l) , size(r)
	local sizeX = sizeL + sizeR + 1
	if sizeL + sizeR <= 1 then
        return Bin(sizeX, k, v, l, r)
	elseif sizeR >= delta*sizeL then
        return rotateL(k, v, l, r)
	elseif sizeL >= delta*sizeR then
        return rotateR(k, v, l, r)
	else
        return Bin(sizeX, k, v, l, r)
	end
end


function rotateL(k, v, l, r)
	local ly, ry = r[Data][4], r[Data][5]
	if size(ly) < ratio * size(ry) then
        return singleL(k, v, l, r)
	else
        return doubleL(k, v, l, r)
	end
end


function rotateR(k, v, l, r)
	local ly, ry = l[Data][4], l[Data][5]
	if size(ry) < ratio * size(ly) then
        return singleR(k, v, l, r)
	else
        return doubleR(k, v, l, r)
	end
end


function singleL(k1, v1, t1, t)
	local _, k2, v2, t2, t3 = table.unpack(t[Data], 1, 5)
	return bin(k2, v2, bin(k1, v1, t1, t2), t3)
end


function singleR(k1, v1, t, t3)
	local _, k2, v2, t1, t2 = table.unpack(t[Data], 1, 5)
	return bin(k2, v2, t1, bin(k1, v1, t2, t3))
end


function doubleL(k1, v1, t1, t)
	local _,k2, v2, tt, t4 = table.unpack(t[Data], 1, 5)
	local _,k3,v3, t2, t3 = table.unpack(tt[Data], 1, 5)
	return bin(k3, v3, bin(k1, v1, t1, t2), bin(k2, v2, t3, t4))
end


function doubleR(k1, v1, t, t4)
    local _, k2, v2, t1, tt = table.unpack(t[Data], 1, 5)
    local _, k3, v3, t2, t3 = table.unpack(tt[Data], 1, 5)
    return bin(k3, v3, bin(k2, v2, t1, t2), bin(k1, v1, t3, t4))
end


-- Construction --

local empty = Tip


local function singleton(k, v) return Bin(1, k, v, Tip, Tip) end


local function insert(kx, x, map)
	if map == Tip then return singleton(kx, x)
	else
		local sz, ky, y, l, r = table.unpack(map[Data], 1, 5)
        local cmp = compare(kx, ky)
		if cmp == LT then
            return balance(ky, y, insert(kx, x, l), r)
		elseif cmp == GT then
            return balance(ky, y, l, insert(kx, x, r))
		else
            return Bin(sz, kx, x, l, r)
		end
	end
end


local function insertWithKey(f, kx, x, map)
    if map == Tip then return singleton(kx, x)
    else
        local sy, ky, y, l, r = table.unpack(map[Data], 1, 5)
        local cmp = compare(kx, ky)
        if cmp == LT then
            return balance(ky, y, insertWithKey(f, kx, x, l), r)
        elseif cmp == GT then
            return balance(ky, y, l, insertWithKey(f, kx, x, r))
        else
            return Bin(sy, kx, f(kx, x, y), l, r)
        end
    end
end


local function insertWith(f, kx, x, map)
    if map == Tip then return singleton(kx, x)
    else
        local sy, ky, y, l, r = table.unpack(map[Data], 1, 5)
        local cmp = compare(kx, ky)
        if cmp == LT then
            return balance(ky, y, insertWith(f, kx, x, l), r)
        elseif cmp == GT then
            return balance(ky, y, l, insertWith(f, kx, x, r))
        else
            return Bin(sy, kx, f(x, y), l, r)
        end
    end
end


local function deleteFindMin(t)
    local _, kx, x, l, r = table.unpack(t[Data], 1, 5)
    if l == Tip then
        return kx, x, r
    else
        local km,m,l_ = deleteFindMin(l)
        return km, m, balance(kx, x, l_, r)
    end
end


local function deleteFindMax(t)
    local _, kx, x, l, r = table.unpack(t[Data], 1, 5)
    if r == Tip then
        return kx, x, l
    else
        local km, m, r_ = deleteFindMax(r)
        return km, m, balance(kx, x, l, r_)
    end
end


local function glue(l, r)
    if l == Tip then
        return r
    elseif r == Tip then
        return l
    elseif size(l) > size(r) then
        local km,m, l_ = deleteFindMax(l)
        return balance(km,m, l_, r)
    else
        local km,m, r_ = deleteFindMin(r)
        return balance(km,m, l, r_)
    end
end


local function delete(k, map)
    if map == Tip then return Tip
    else
        local _, kx, x, l, r = table.unpack(map[Data], 1, 5)
        local cmp = compare(k, kx)
        if cmp == EQ then
            return glue(l, r)
        elseif cmp == LT then
            return balance(kx, x, delete(k, l), r)
        else
            return balance(kx, x, l, delete(k, r))
        end
    end
end


local function foldRWithKey(f, acc, map)
    if map == Tip then return acc
    else
        local _, kx, x, l, r = table.unpack(map[Data], 1, 5)
        return foldRWithKey(f, f(kx, x, foldRWithKey(f, acc, r)), l)
    end
end


local function foldR(f, acc, map)
    if map == Tip then return acc
    else
        local _, _, x, l, r = table.unpack(map[Data], 1, 5)
        return foldR(f, f(x, foldR(f, acc, r)), l)
    end
end


local function each(f, map)
    if map ~= Tip then
        local _, kx, x, l, r = table.unpack(map[Data], 1, 5)
        each(f, l)
        f(kx, x)
        each(f, r)
    end
end


local PLACEHOLDER = setmetatable({}, {__tostring = function() return "nil(placeholder)" end})

local function eachWithT(f, map)
    if map ~= Tip then
        local _, kx, x, l, r = table.unpack(map[Data], 1, 5)

        eachWithT(f, l)
        if kx == nil then
            f(PLACEHOLDER, x)
        else
            f(kx, x)
        end
        eachWithT(f, r)
    end
end


local function fromTable(t)
    local m = empty
    for k, v in pairs(t) do
        m = insert(k, v, m)
    end
    return m
end


local function equal(self, other)
    if self == Tip or other == Tip then return self == other end
    if getmetatable(other) == map_t then
        local iter1, invar1, state1 = pairs(self)
        local iter2, invar2, state2 = pairs(other)
        repeat
            local v1, v2
            state1, v1 = iter1(invar1, state1)
            state2, v2 = iter2(invar2, state2)
            if not (equal(v1, v2) and equal(state1, state2)) then
                return false
            end
        until state1 == nil or state2 == nil

        return state1 == nil and state2 == nil
    else
        return self == other
    end
end


-- Interface --

function map_t:__len() return size(self) end


function map_t:__call(k, ...)
    if select('#', ...) == 0 then
        return function(v) return insert(k, v, self) end
    else
        return insert(k, ..., self)
    end
end


function map_t:__index(k) return lookup(k, self) end


local function pairs_wrapper(map)
    return eachWithT(coroutine.yield, map)
end

function map_t:__pairs()
    return coroutine.wrap(pairs_wrapper), self
end


function map_t:__shl(other)
    if getmetatable(self) == map_t then
        for k, v in pairs(other) do
            if k == PLACEHOLDER then self = insert(nil, v, self)
            else
                self = insert(k, v, self)
            end
        end
        return self
    else
        return error("Use (<<) on maps to add values, e.g: map.empty << {x = 2}")
    end
end

function map_t:__tostring()
    local buf = {}
    for k , v in pairs(self) do
        local ks, vs

        if k == PLACEHOLDER then
            ks = 'nil'
        elseif type(k) == 'string' then
            ks = ("%q"):format(k)
            if ks == ('"' .. k .. '"') then
                ks = k
            end
        else
            ks = tostring(k)
        end

        if type(v) == 'string' then
            vs = ("%q"):format(v)
        else
            vs = tostring(v)
        end
        table.insert(buf, ("%s = %s"):format(ks, vs))
    end
    return "map{".. table.concat(buf, ", ").."}"
end

function map_t:__map_hash()
    local buf = {}
    for k, v in pairs(self) do
        if k == PLACEHOLDER then table.insert(buf, hash(nil) .. hash(v))
        else
            table.insert(buf, hash(k) .. hash(v))
        end
    end
    return ("J"):pack(size(self)) .. table.concat(buf)
end
mts[map_t] = {255}

module = setmetatable({
    empty = empty,
    insert = insert,
    null = null,
    size = size,
    lookup = lookup,
    missing = missing,
    insertWith = insertWith,
    insertWithKey = insertWithKey,
    delete = delete,
    foldRWithKey = foldRWithKey,
    foldR = foldR,
    each = each,
    fromTable = fromTable,
    nilp = PLACEHOLDER,
    equal = equal
}, {__call = function(_,...) return fromTable(...) end})

end



return module
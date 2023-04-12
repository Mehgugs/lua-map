# map.lua

An implementation of the Data.Map from haskell in lua.

## About

This single file module implements an immutable map structure, with
some common operations for manipulating them included.

This map can store any lua value pairing, and is naturally sorted. It should be noted the ordering of reference types uses the address of the object, and thus you may have
undesirable behaviour when using complex user-defined types as keys. You can return a string hash via
the `__map_hash` metamethod, which should be visible on the metatable for your type.
Due to how types are ordered there can be a maximum of 254 complex types interned to this module at any one time.

Prior to lua 5.4 the only reliable way to retrieve an address of a reference type was by using the default `tostring` value, and therefore on versions below 5.4 that is used to retrieve an address. If you are using a version of lua which has a modified base library, this may cause issues.

## Reference

#### *map* `empty`

This is the empty map.


#### *number (integer)* `size(map)`

- *map* `map`

Returns the number of elements contained in the map.

#### *map* `insert(k, v, map)` **OR** `map << {k = v, ...}`

- *anything* `k`
- *anything* `v`
- *map* `map`

Adds a key-value pair into the map, returning the updated map. You can call this with a table of key-value pairs using the `<<` operator.

```lua
local myMap = map.insert('y', 2, map.insert('x', 1, map.empty))
local myMap = map.empty << {x = 1, y = 2}
local myMap = map.empty << {x = 1} << {y = 2}
```

#### *anything, bool?* `lookup(k, map)` **OR** `map[k]`

- *anything* `k`
- *map* `map`

Returns the value stored in the map, or nil if it does not exist.

The value `true` is additionally returned if the value was actually missing from the map,
this is so `nil` values stored within the map are observable.

#### *bool* `missing(k, map)`

- *anything* `k`
- *map* `map`

Returns the second argument of `lookup` directly, defaulting to `false`.

#### *map* `insertWith(f, k, v, map)`

- *function(old, new) return anything* `f`
- *anything* `k`
- *anything* `v`
- *map* `map`

Inserts a key value pair into the map,
calling the function `f` with the old value and the new value
if there's already a pair in the map.

**Example**

```lua
local myMap = map.fromTable {x = 1}

myMap = map.insertWith(function(a, b) return a + b end, 'x', 1, myMap)

print(myMap.x) --> 2
```

#### *map* `insertWithKey(f, k, v, map)`

- *function(key, old, new) return anything* `f`
- *anything* `k`
- *anything* `v`
- *map* `map`

The same as insertWith, but the function receives the key as an additional argument.

#### *map* `delete(k, map)`

- *anything* `k`
- *map* `map`

Removes a key-value pair from the map.

**Example**
```lua
local myMap = map.fromTable {"🚗", "🚓", "🚕"}

print(delete(1, map >> 3)[2]) --> 🚓
```

#### *anything* `foldR(f, acc, map)`

- *function(val, acc) return anything* `f`
- *anything* `acc` The initial value to fold with.
- *map* `map`

Performs a right handed fold across the map.

**Example**
```lua
local myMap = map.fromTable{1,2,3,4}

map.foldR(function(x, acc) return x + acc end, 0, myMap) -- 10

--- This is the "same" as calculating:

local f = function(x, acc) return x + acc end

f(1, f(2, f(3, f(4, 0))))

--- Another example:

local function insert(t, ...)
    table.insert(t, ...)
    return t
end

local res = map.foldR(insert, {}, myMap) -- {4,3,2,1}
```

#### *anything* `foldRWithKey(f, acc, map)`

- *function(key, val, acc) return anything* `f`
- *anything* `acc` The initial value to fold with.
- *map* `map`

Performs a right handed fold across the map, the key is passed to the folding function as the first argument.

#### *nil* `each(f, map)`

- *function(key, value) return anything* f
- *map* map

Calls function `f` on each key value pair of the map.


#### *bool* `equal(map1, map2)`

- *anything* `map1`
- *anything* `map2`

Tests for deep equality between maps, and uses regular `==` for everything else. `==` is still reference equality on maps.

This function always uses equality to test the contents of two maps, not the ordinal/hash computed. It is the responsibility of people implementing `__map_hash` to ensure the semantics of `==` are preserved in the hash, if that is what you want (it almost always will be).


#### *iterator* `pairs(map)`

Iterates over the key-value pairs of the map. Due to the order imposed on map keys, this function will always iterate in the same order for a given map.

**Example**

```lua
for k , v in pairs(map.fromTable{1,2,3,4}) do
    print(k, v)
end
-- prints:
-- 1    1
-- 2    2
-- 3    3
-- 4    4
```

#### *map* *`map`*`(key, value)`

- *anything* `key`
- *anything* `value` optional.

The call metamethod on maps is an alias for insert. This can be partially applied by calling it with one argument.

```lua

local origin = map.fromTable{x = 0, y = 0}

local withY = origin'y'

withY(12) -- map{x = 0, y = 12}

origin('x', 11) -- map{x = 11, y = 0}
```



--!strict
local AbiCodec = require("../../src/contract/AbiCodec")

--------------------------------------------------------------------------------
-- Test helpers
--------------------------------------------------------------------------------

--- Build a minimal typeMap with just built-in types
local function builtinTypeMap(): AbiCodec.TypeMap
	return AbiCodec.buildTypeMap({})
end

--- Build a typeMap with a custom struct
local function typeMapWithStruct(
	structName: string,
	members: { { name: string, type: string } }
): AbiCodec.TypeMap
	local abi: { any } = {
		{ type = "struct", name = structName, members = members },
	}
	return AbiCodec.buildTypeMap(abi)
end

--- Build a typeMap with a custom enum
local function typeMapWithEnum(
	enumName: string,
	variants: { { name: string, type: string } }
): AbiCodec.TypeMap
	local abi: { any } = {
		{ type = "enum", name = enumName, variants = variants },
	}
	return AbiCodec.buildTypeMap(abi)
end

--------------------------------------------------------------------------------
-- buildTypeMap
--------------------------------------------------------------------------------

describe("AbiCodec.buildTypeMap - struct parsing", function()
	it("parses a struct with felt members", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local def = tm["mymod::Point"]
		expect(def):toBeTruthy()
		expect(def.kind):toBe("struct")
		expect(#(def.members :: any)):toBe(2)
		expect((def.members :: any)[1].name):toBe("x")
		expect((def.members :: any)[2].name):toBe("y")
	end)

	it("parses a struct with mixed types", function()
		local tm = typeMapWithStruct("mymod::Account", {
			{ name = "address", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "balance", type = "core::integer::u256" },
			{ name = "active", type = "core::bool" },
		})
		local def = tm["mymod::Account"]
		expect(def):toBeTruthy()
		expect(#(def.members :: any)):toBe(3)
	end)

	it("registers built-in aliases", function()
		local tm = builtinTypeMap()
		expect(tm["core::felt252"]):toBeTruthy()
		expect(tm["felt252"]):toBeTruthy()
		expect(tm["core::bool"]):toBeTruthy()
		expect(tm["bool"]):toBeTruthy()
		expect(tm["core::integer::u256"]):toBeTruthy()
		expect(tm["u256"]):toBeTruthy()
		expect(tm["()"]):toBeTruthy()
		expect(tm["core::byte_array::ByteArray"]):toBeTruthy()
	end)

	it("handles empty ABI", function()
		local tm = AbiCodec.buildTypeMap({})
		-- Should still have built-in types
		expect(tm["core::felt252"]):toBeTruthy()
	end)

	it("skips core::bool enum to avoid overriding built-in", function()
		local abi: { any } = {
			{
				type = "enum",
				name = "core::bool",
				variants = {
					{ name = "False", type = "()" },
					{ name = "True", type = "()" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		-- core::bool should still be kind=bool, not kind=enum
		expect(tm["core::bool"].kind):toBe("bool")
	end)

	it("handles duplicate struct definitions (last wins)", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Foo",
				members = { { name = "a", type = "core::felt252" } },
			},
			{
				type = "struct",
				name = "mymod::Foo",
				members = {
					{ name = "a", type = "core::felt252" },
					{ name = "b", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		expect(#(tm["mymod::Foo"].members :: any)):toBe(2)
	end)
end)

describe("AbiCodec.buildTypeMap - enum parsing", function()
	it("parses a custom enum", function()
		local tm = typeMapWithEnum("mymod::Status", {
			{ name = "Active", type = "()" },
			{ name = "Paused", type = "()" },
			{ name = "Stopped", type = "core::felt252" },
		})
		local def = tm["mymod::Status"]
		expect(def):toBeTruthy()
		expect(def.kind):toBe("enum")
		expect(#(def.variants :: any)):toBe(3)
	end)

	it("skips core::option::Option enum definition", function()
		local abi: { any } = {
			{
				type = "enum",
				name = "core::option::Option::<core::felt252>",
				variants = {
					{ name = "Some", type = "core::felt252" },
					{ name = "None", type = "()" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		-- Should NOT be stored — resolved dynamically via generic parsing
		expect(tm["core::option::Option::<core::felt252>"]):toBeFalsy()
	end)

	it("skips core::result::Result enum definition", function()
		local abi: { any } = {
			{
				type = "enum",
				name = "core::result::Result::<core::felt252, core::felt252>",
				variants = {
					{ name = "Ok", type = "core::felt252" },
					{ name = "Err", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		expect(tm["core::result::Result::<core::felt252, core::felt252>"]):toBeFalsy()
	end)
end)

--------------------------------------------------------------------------------
-- resolveType
--------------------------------------------------------------------------------

describe("AbiCodec.resolveType", function()
	it("resolves Array generic", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("core::array::Array::<core::felt252>", tm)
		expect(def.kind):toBe("array")
		expect(def.elementType):toBe("core::felt252")
	end)

	it("resolves Span generic (same as Array)", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("core::array::Span::<core::felt252>", tm)
		expect(def.kind):toBe("array")
		expect(def.elementType):toBe("core::felt252")
	end)

	it("resolves Option generic as synthetic enum", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("core::option::Option::<core::felt252>", tm)
		expect(def.kind):toBe("enum")
		expect(#(def.variants :: any)):toBe(2)
		expect((def.variants :: any)[1].name):toBe("Some")
		expect((def.variants :: any)[1].type):toBe("core::felt252")
		expect((def.variants :: any)[2].name):toBe("None")
	end)

	it("resolves Result generic as synthetic enum", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("core::result::Result::<core::felt252, core::integer::u256>", tm)
		expect(def.kind):toBe("enum")
		expect(#(def.variants :: any)):toBe(2)
		expect((def.variants :: any)[1].name):toBe("Ok")
		expect((def.variants :: any)[1].type):toBe("core::felt252")
		expect((def.variants :: any)[2].name):toBe("Err")
		expect((def.variants :: any)[2].type):toBe("core::integer::u256")
	end)

	it("resolves tuple type", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("(core::felt252, core::bool)", tm)
		expect(def.kind):toBe("tuple")
		expect(#(def.tupleTypes :: any)):toBe(2)
		expect((def.tupleTypes :: any)[1]):toBe("core::felt252")
		expect((def.tupleTypes :: any)[2]):toBe("core::bool")
	end)

	it("resolves nested generic (Array of structs)", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local def = AbiCodec.resolveType("core::array::Array::<mymod::Point>", tm)
		expect(def.kind):toBe("array")
		expect(def.elementType):toBe("mymod::Point")
	end)

	it("falls back to felt for unknown type", function()
		local tm = builtinTypeMap()
		local def = AbiCodec.resolveType("some::unknown::Type", tm)
		expect(def.kind):toBe("felt")
	end)

	it("caches resolved generics", function()
		local tm = builtinTypeMap()
		AbiCodec.resolveType("core::array::Array::<core::felt252>", tm)
		-- Should be cached now
		expect(tm["core::array::Array::<core::felt252>"]):toBeTruthy()
		expect(tm["core::array::Array::<core::felt252>"].kind):toBe("array")
	end)

	it("resolves integer types as felt", function()
		local tm = builtinTypeMap()
		expect(AbiCodec.resolveType("core::integer::u8", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("core::integer::u16", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("core::integer::u32", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("core::integer::u64", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("core::integer::u128", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("u8", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("u128", tm).kind):toBe("felt")
		expect(AbiCodec.resolveType("i32", tm).kind):toBe("felt")
	end)
end)

--------------------------------------------------------------------------------
-- encode primitives
--------------------------------------------------------------------------------

describe("AbiCodec.encode - primitives", function()
	it("encodes felt252", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("0xabc", "core::felt252", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0xabc")
	end)

	it("encodes felt252 short name", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("0x1", "felt252", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x1")
	end)

	it("encodes bool true", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(true, "core::bool", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x1")
	end)

	it("encodes bool false", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(false, "bool", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x0")
	end)

	it("encodes u256 into 2 felts", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("0x3e8", "core::integer::u256", tm)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x3e8") -- low
		expect(r[2]):toBe("0x0") -- high
	end)

	it("encodes u8 as single felt", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("0x42", "core::integer::u8", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x42")
	end)

	it("encodes ContractAddress as felt", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("0xdeadbeef", "core::starknet::contract_address::ContractAddress", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0xdeadbeef")
	end)

	it("encodes unit as empty", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(nil, "()", tm)
		expect(#r):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- encode struct
--------------------------------------------------------------------------------

describe("AbiCodec.encode - struct", function()
	it("encodes flat struct", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local r = AbiCodec.encode({ x = "0x1", y = "0x2" }, "mymod::Point", tm)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x2")
	end)

	it("encodes nested struct", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Inner",
				members = { { name = "val", type = "core::felt252" } },
			},
			{
				type = "struct",
				name = "mymod::Outer",
				members = {
					{ name = "id", type = "core::felt252" },
					{ name = "inner", type = "mymod::Inner" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode({
			id = "0xa",
			inner = { val = "0xb" },
		}, "mymod::Outer", tm)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0xa")
		expect(r[2]):toBe("0xb")
	end)

	it("encodes struct with u256 member", function()
		local tm = typeMapWithStruct("mymod::Balance", {
			{ name = "owner", type = "core::felt252" },
			{ name = "amount", type = "core::integer::u256" },
		})
		local r = AbiCodec.encode({ owner = "0xabc", amount = "0x3e8" }, "mymod::Balance", tm)
		expect(#r):toBe(3) -- 1 felt + 2 felts (u256)
		expect(r[1]):toBe("0xabc")
		expect(r[2]):toBe("0x3e8") -- low
		expect(r[3]):toBe("0x0") -- high
	end)

	it("encodes struct with bool member", function()
		local tm = typeMapWithStruct("mymod::Flag", {
			{ name = "id", type = "core::felt252" },
			{ name = "active", type = "core::bool" },
		})
		local r = AbiCodec.encode({ id = "0x1", active = true }, "mymod::Flag", tm)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x1")
	end)

	it("encodes single-member struct", function()
		local tm = typeMapWithStruct("mymod::Wrapper", {
			{ name = "value", type = "core::felt252" },
		})
		local r = AbiCodec.encode({ value = "0x42" }, "mymod::Wrapper", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x42")
	end)
end)

--------------------------------------------------------------------------------
-- encode enum
--------------------------------------------------------------------------------

describe("AbiCodec.encode - enum", function()
	it("encodes unit variant (index 0)", function()
		local tm = typeMapWithEnum("mymod::Status", {
			{ name = "Active", type = "()" },
			{ name = "Paused", type = "()" },
		})
		local r = AbiCodec.encode({ variant = "Active", value = nil }, "mymod::Status", tm)
		expect(#r):toBe(1) -- just the variant index, unit has 0 felts
		expect(r[1]):toBe("0x0")
	end)

	it("encodes unit variant (index 1)", function()
		local tm = typeMapWithEnum("mymod::Status", {
			{ name = "Active", type = "()" },
			{ name = "Paused", type = "()" },
		})
		local r = AbiCodec.encode({ variant = "Paused", value = nil }, "mymod::Status", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x1")
	end)

	it("encodes variant with felt data", function()
		local tm = typeMapWithEnum("mymod::Action", {
			{ name = "Send", type = "core::felt252" },
			{ name = "Receive", type = "core::felt252" },
		})
		local r = AbiCodec.encode({ variant = "Send", value = "0xabc" }, "mymod::Action", tm)
		expect(#r):toBe(2) -- index + felt
		expect(r[1]):toBe("0x0")
		expect(r[2]):toBe("0xabc")
	end)

	it("encodes variant with struct data", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Point",
				members = {
					{ name = "x", type = "core::felt252" },
					{ name = "y", type = "core::felt252" },
				},
			},
			{
				type = "enum",
				name = "mymod::Shape",
				variants = {
					{ name = "Circle", type = "core::felt252" },
					{ name = "Point", type = "mymod::Point" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode(
			{ variant = "Point", value = { x = "0x1", y = "0x2" } },
			"mymod::Shape",
			tm
		)
		expect(#r):toBe(3) -- index + 2 struct felts
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
	end)

	it("encodes multi-variant with correct index", function()
		local tm = typeMapWithEnum("mymod::Color", {
			{ name = "Red", type = "()" },
			{ name = "Green", type = "()" },
			{ name = "Blue", type = "()" },
		})
		local r = AbiCodec.encode({ variant = "Blue", value = nil }, "mymod::Color", tm)
		expect(r[1]):toBe("0x2")
	end)
end)

--------------------------------------------------------------------------------
-- encode Option
--------------------------------------------------------------------------------

describe("AbiCodec.encode - Option", function()
	it("encodes Some(felt)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode({ Some = "0x42" }, "core::option::Option::<core::felt252>", tm)
		expect(#r):toBe(2) -- index(0) + felt
		expect(r[1]):toBe("0x0") -- Some = index 0
		expect(r[2]):toBe("0x42")
	end)

	it("encodes None", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode({ None = true }, "core::option::Option::<core::felt252>", tm)
		expect(#r):toBe(1) -- index(1) + unit(0 felts)
		expect(r[1]):toBe("0x1") -- None = index 1
	end)

	it("encodes Some(u256)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode({ Some = "0xff" }, "core::option::Option::<core::integer::u256>", tm)
		expect(#r):toBe(3) -- index + low + high
		expect(r[1]):toBe("0x0")
		expect(r[2]):toBe("0xff")
		expect(r[3]):toBe("0x0")
	end)

	it("encodes Some(struct)", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Pair",
				members = {
					{ name = "a", type = "core::felt252" },
					{ name = "b", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode(
			{ Some = { a = "0x1", b = "0x2" } },
			"core::option::Option::<mymod::Pair>",
			tm
		)
		expect(#r):toBe(3) -- index + 2 struct felts
		expect(r[1]):toBe("0x0")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
	end)

	it("encodes nil as None", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(nil, "core::option::Option::<core::felt252>", tm)
		expect(r[1]):toBe("0x1") -- None
	end)
end)

--------------------------------------------------------------------------------
-- encode Result
--------------------------------------------------------------------------------

describe("AbiCodec.encode - Result", function()
	it("encodes Ok(felt)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ Ok = "0x42" },
			"core::result::Result::<core::felt252, core::felt252>",
			tm
		)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x0") -- Ok = index 0
		expect(r[2]):toBe("0x42")
	end)

	it("encodes Err(felt)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ Err = "0xff" },
			"core::result::Result::<core::felt252, core::felt252>",
			tm
		)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x1") -- Err = index 1
		expect(r[2]):toBe("0xff")
	end)

	it("encodes Ok(struct)", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Data",
				members = {
					{ name = "x", type = "core::felt252" },
					{ name = "y", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode(
			{ Ok = { x = "0x1", y = "0x2" } },
			"core::result::Result::<mymod::Data, core::felt252>",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x0")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
	end)

	it("encodes Err(u256)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ Err = "0x100" },
			"core::result::Result::<core::felt252, core::integer::u256>",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x1") -- Err
		expect(r[2]):toBe("0x100") -- low
		expect(r[3]):toBe("0x0") -- high
	end)
end)

--------------------------------------------------------------------------------
-- encode Array
--------------------------------------------------------------------------------

describe("AbiCodec.encode - Array", function()
	it("encodes Array<felt252>", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ "0x1", "0x2", "0x3" },
			"core::array::Array::<core::felt252>",
			tm
		)
		expect(#r):toBe(4) -- length + 3 elements
		expect(r[1]):toBe("0x3")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
		expect(r[4]):toBe("0x3")
	end)

	it("encodes Array<u256>", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ "0xa", "0xb" },
			"core::array::Array::<core::integer::u256>",
			tm
		)
		expect(#r):toBe(5) -- length + 2*(low,high)
		expect(r[1]):toBe("0x2")
		expect(r[2]):toBe("0xa") -- first u256 low
		expect(r[3]):toBe("0x0") -- first u256 high
		expect(r[4]):toBe("0xb") -- second u256 low
		expect(r[5]):toBe("0x0") -- second u256 high
	end)

	it("encodes Array<struct>", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local r = AbiCodec.encode(
			{ { x = "0x1", y = "0x2" }, { x = "0x3", y = "0x4" } },
			"core::array::Array::<mymod::Point>",
			tm
		)
		expect(#r):toBe(5) -- length + 2*2 struct felts
		expect(r[1]):toBe("0x2")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
		expect(r[4]):toBe("0x3")
		expect(r[5]):toBe("0x4")
	end)

	it("encodes empty array", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode({}, "core::array::Array::<core::felt252>", tm)
		expect(#r):toBe(1)
		expect(r[1]):toBe("0x0")
	end)

	it("encodes Array<bool>", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ true, false, true },
			"core::array::Array::<core::bool>",
			tm
		)
		expect(#r):toBe(4)
		expect(r[1]):toBe("0x3")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x0")
		expect(r[4]):toBe("0x1")
	end)
end)

--------------------------------------------------------------------------------
-- encode Span
--------------------------------------------------------------------------------

describe("AbiCodec.encode - Span", function()
	it("encodes Span<felt252> same as Array", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ "0xa", "0xb" },
			"core::array::Span::<core::felt252>",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x2")
		expect(r[2]):toBe("0xa")
		expect(r[3]):toBe("0xb")
	end)

	it("encodes Span<struct>", function()
		local tm = typeMapWithStruct("mymod::Pair", {
			{ name = "a", type = "core::felt252" },
			{ name = "b", type = "core::felt252" },
		})
		local r = AbiCodec.encode(
			{ { a = "0x1", b = "0x2" } },
			"core::array::Span::<mymod::Pair>",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x1") -- length
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
	end)
end)

--------------------------------------------------------------------------------
-- encode tuple
--------------------------------------------------------------------------------

describe("AbiCodec.encode - tuple", function()
	it("encodes (felt, felt)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode({ "0x1", "0x2" }, "(core::felt252, core::felt252)", tm)
		expect(#r):toBe(2)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x2")
	end)

	it("encodes (felt, u256, bool)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{ "0xa", "0xff", true },
			"(core::felt252, core::integer::u256, core::bool)",
			tm
		)
		expect(#r):toBe(4) -- 1 + 2 + 1
		expect(r[1]):toBe("0xa")
		expect(r[2]):toBe("0xff")
		expect(r[3]):toBe("0x0")
		expect(r[4]):toBe("0x1")
	end)

	it("encodes (struct, felt)", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local r = AbiCodec.encode(
			{ { x = "0x1", y = "0x2" }, "0x3" },
			"(mymod::Point, core::felt252)",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x2")
		expect(r[3]):toBe("0x3")
	end)

	it("encodes nested tuple", function()
		local tm = builtinTypeMap()
		-- Nested: (felt, (felt, felt))
		local r = AbiCodec.encode(
			{ "0xa", { "0xb", "0xc" } },
			"(core::felt252, (core::felt252, core::felt252))",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0xa")
		expect(r[2]):toBe("0xb")
		expect(r[3]):toBe("0xc")
	end)
end)

--------------------------------------------------------------------------------
-- encode ByteArray
--------------------------------------------------------------------------------

describe("AbiCodec.encode - ByteArray", function()
	it("encodes short string (< 31 chars)", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode("Hello", "core::byte_array::ByteArray", tm)
		-- 0 full chunks + pending "Hello" (5 bytes) + pending_len=5
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x0") -- num_full_chunks
		expect(r[2]):toBe("0x48656c6c6f") -- "Hello" as hex
		expect(r[3]):toBe("0x5") -- pending_word_len
	end)

	it("encodes exactly 31 chars", function()
		local str = "1234567890123456789012345678901" -- 31 chars
		local r = AbiCodec.encodeByteArray(str)
		-- [num_chunks=1, chunk_hex, pending_word=0x0, pending_len=0x0]
		expect(#r):toBe(4)
		expect(r[1]):toBe("0x1") -- 1 full chunk
		-- r[2] is the 31-byte chunk hex
		expect(r[3]):toBe("0x0") -- pending word (empty)
		expect(r[4]):toBe("0x0") -- pending len
	end)

	it("encodes 35 chars (1 full chunk + 4 pending)", function()
		local str = "12345678901234567890123456789012345" -- 35 chars
		local r = AbiCodec.encodeByteArray(str)
		-- 1 full chunk (31 bytes) + 4 pending bytes
		expect(#r):toBe(4)
		expect(r[1]):toBe("0x1") -- 1 full chunk
		-- r[2] = 31-byte chunk
		-- r[3] = pending "2345" hex
		expect(r[3]):toBe("0x32333435") -- "2345"
		expect(r[4]):toBe("0x4") -- pending len = 4
	end)

	it("encodes empty string", function()
		local r = AbiCodec.encodeByteArray("")
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x0") -- 0 chunks
		expect(r[2]):toBe("0x0") -- pending word
		expect(r[3]):toBe("0x0") -- pending len
	end)

	it("encodes long multi-chunk string", function()
		-- 62 chars = 2 full chunks (31*2) + 0 pending
		local str = string.rep("A", 62)
		local r = AbiCodec.encodeByteArray(str)
		expect(#r):toBe(5) -- num_chunks + chunk0 + chunk1 + pending + pending_len
		expect(r[1]):toBe("0x2") -- 2 full chunks
		expect(r[4]):toBe("0x0") -- pending word
		expect(r[5]):toBe("0x0") -- pending len
	end)
end)

--------------------------------------------------------------------------------
-- decode primitives
--------------------------------------------------------------------------------

describe("AbiCodec.decode - primitives", function()
	it("decodes felt", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode({ "0xabc" }, 1, "core::felt252", tm)
		expect(val):toBe("0xabc")
		expect(consumed):toBe(1)
	end)

	it("decodes bool true", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode({ "0x1" }, 1, "core::bool", tm)
		expect(val):toBe(true)
		expect(consumed):toBe(1)
	end)

	it("decodes bool false", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode({ "0x0" }, 1, "core::bool", tm)
		expect(val):toBe(false)
		expect(consumed):toBe(1)
	end)

	it("decodes u256", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode({ "0x3e8", "0x0" }, 1, "core::integer::u256", tm)
		expect((val :: any).low):toBe("0x3e8")
		expect((val :: any).high):toBe("0x0")
		expect(consumed):toBe(2)
	end)

	it("decodes unit", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode({ "0x1" }, 1, "()", tm)
		expect(val):toBeFalsy() -- nil
		expect(consumed):toBe(0)
	end)

	it("decodes ContractAddress as felt", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0xdeadbeef" },
			1,
			"core::starknet::contract_address::ContractAddress",
			tm
		)
		expect(val):toBe("0xdeadbeef")
		expect(consumed):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- decode struct
--------------------------------------------------------------------------------

describe("AbiCodec.decode - struct", function()
	it("decodes flat struct", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local val, consumed = AbiCodec.decode({ "0x1", "0x2" }, 1, "mymod::Point", tm)
		expect((val :: any).x):toBe("0x1")
		expect((val :: any).y):toBe("0x2")
		expect(consumed):toBe(2)
	end)

	it("decodes nested struct", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Inner",
				members = { { name = "val", type = "core::felt252" } },
			},
			{
				type = "struct",
				name = "mymod::Outer",
				members = {
					{ name = "id", type = "core::felt252" },
					{ name = "inner", type = "mymod::Inner" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local val, consumed = AbiCodec.decode({ "0xa", "0xb" }, 1, "mymod::Outer", tm)
		expect((val :: any).id):toBe("0xa")
		expect((val :: any).inner.val):toBe("0xb")
		expect(consumed):toBe(2)
	end)

	it("decodes struct with mixed types", function()
		local tm = typeMapWithStruct("mymod::Mixed", {
			{ name = "addr", type = "core::felt252" },
			{ name = "amount", type = "core::integer::u256" },
			{ name = "flag", type = "core::bool" },
		})
		local val, consumed = AbiCodec.decode(
			{ "0xabc", "0x3e8", "0x0", "0x1" },
			1,
			"mymod::Mixed",
			tm
		)
		expect((val :: any).addr):toBe("0xabc")
		expect((val :: any).amount.low):toBe("0x3e8")
		expect((val :: any).amount.high):toBe("0x0")
		expect((val :: any).flag):toBe(true)
		expect(consumed):toBe(4)
	end)
end)

--------------------------------------------------------------------------------
-- decode enum
--------------------------------------------------------------------------------

describe("AbiCodec.decode - enum", function()
	it("decodes unit variant", function()
		local tm = typeMapWithEnum("mymod::Status", {
			{ name = "Active", type = "()" },
			{ name = "Paused", type = "()" },
		})
		local val, consumed = AbiCodec.decode({ "0x0" }, 1, "mymod::Status", tm)
		expect((val :: any).variant):toBe("Active")
		expect(consumed):toBe(1) -- index + 0 unit felts
	end)

	it("decodes data variant", function()
		local tm = typeMapWithEnum("mymod::Action", {
			{ name = "Send", type = "core::felt252" },
			{ name = "Idle", type = "()" },
		})
		local val, consumed = AbiCodec.decode({ "0x0", "0xabc" }, 1, "mymod::Action", tm)
		expect((val :: any).variant):toBe("Send")
		expect((val :: any).value):toBe("0xabc")
		expect(consumed):toBe(2)
	end)

	it("decodes Option Some", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x0", "0x42" },
			1,
			"core::option::Option::<core::felt252>",
			tm
		)
		expect((val :: any).variant):toBe("Some")
		expect((val :: any).value):toBe("0x42")
		expect(consumed):toBe(2)
	end)

	it("decodes Option None", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x1" },
			1,
			"core::option::Option::<core::felt252>",
			tm
		)
		expect((val :: any).variant):toBe("None")
		expect(consumed):toBe(1)
	end)

	it("decodes Result Ok", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x0", "0x42" },
			1,
			"core::result::Result::<core::felt252, core::felt252>",
			tm
		)
		expect((val :: any).variant):toBe("Ok")
		expect((val :: any).value):toBe("0x42")
		expect(consumed):toBe(2)
	end)

	it("decodes Result Err", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x1", "0xff" },
			1,
			"core::result::Result::<core::felt252, core::felt252>",
			tm
		)
		expect((val :: any).variant):toBe("Err")
		expect((val :: any).value):toBe("0xff")
		expect(consumed):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- decode Array
--------------------------------------------------------------------------------

describe("AbiCodec.decode - Array", function()
	it("decodes Array<felt252>", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x3", "0xa", "0xb", "0xc" },
			1,
			"core::array::Array::<core::felt252>",
			tm
		)
		local arr = val :: { any }
		expect(#arr):toBe(3)
		expect(arr[1]):toBe("0xa")
		expect(arr[2]):toBe("0xb")
		expect(arr[3]):toBe("0xc")
		expect(consumed):toBe(4)
	end)

	it("decodes Array<struct>", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local val, consumed = AbiCodec.decode(
			{ "0x2", "0x1", "0x2", "0x3", "0x4" },
			1,
			"core::array::Array::<mymod::Point>",
			tm
		)
		local arr = val :: { any }
		expect(#arr):toBe(2)
		expect(arr[1].x):toBe("0x1")
		expect(arr[1].y):toBe("0x2")
		expect(arr[2].x):toBe("0x3")
		expect(arr[2].y):toBe("0x4")
		expect(consumed):toBe(5)
	end)

	it("decodes empty Array", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x0" },
			1,
			"core::array::Array::<core::felt252>",
			tm
		)
		expect(#(val :: { any })):toBe(0)
		expect(consumed):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- decode tuple
--------------------------------------------------------------------------------

describe("AbiCodec.decode - tuple", function()
	it("decodes simple tuple", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0x1", "0x2" },
			1,
			"(core::felt252, core::felt252)",
			tm
		)
		local arr = val :: { any }
		expect(#arr):toBe(2)
		expect(arr[1]):toBe("0x1")
		expect(arr[2]):toBe("0x2")
		expect(consumed):toBe(2)
	end)

	it("decodes mixed-type tuple", function()
		local tm = builtinTypeMap()
		local val, consumed = AbiCodec.decode(
			{ "0xa", "0xff", "0x0", "0x1" },
			1,
			"(core::felt252, core::integer::u256, core::bool)",
			tm
		)
		local arr = val :: { any }
		expect(#arr):toBe(3)
		expect(arr[1]):toBe("0xa")
		expect(arr[2].low):toBe("0xff")
		expect(arr[2].high):toBe("0x0")
		expect(arr[3]):toBe(true)
		expect(consumed):toBe(4)
	end)
end)

--------------------------------------------------------------------------------
-- decode ByteArray
--------------------------------------------------------------------------------

describe("AbiCodec.decode - ByteArray", function()
	it("decodes short string", function()
		local tm = builtinTypeMap()
		-- "Hello" = 0 chunks, pending=0x48656c6c6f, len=5
		local val, consumed = AbiCodec.decode(
			{ "0x0", "0x48656c6c6f", "0x5" },
			1,
			"core::byte_array::ByteArray",
			tm
		)
		expect(val):toBe("Hello")
		expect(consumed):toBe(3)
	end)

	it("decodes multi-chunk string", function()
		-- Build a 35-char string: 1 full chunk + 4 pending
		local str = "12345678901234567890123456789012345"
		local encoded = AbiCodec.encodeByteArray(str)

		local val, consumed = AbiCodec.decodeByteArray(encoded, 1)
		expect(val):toBe(str)
		expect(consumed):toBe(#encoded)
	end)

	it("decodes empty string", function()
		local val, consumed = AbiCodec.decodeByteArray({ "0x0", "0x0", "0x0" }, 1)
		expect(val):toBe("")
		expect(consumed):toBe(3)
	end)
end)

--------------------------------------------------------------------------------
-- round-trip tests (encode → decode)
--------------------------------------------------------------------------------

describe("AbiCodec - round-trip encode/decode", function()
	it("round-trips felt252", function()
		local tm = builtinTypeMap()
		local encoded = AbiCodec.encode("0x42", "core::felt252", tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, "core::felt252", tm)
		expect(decoded):toBe("0x42")
	end)

	it("round-trips bool", function()
		local tm = builtinTypeMap()
		local encoded = AbiCodec.encode(true, "core::bool", tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, "core::bool", tm)
		expect(decoded):toBe(true)
	end)

	it("round-trips u256", function()
		local tm = builtinTypeMap()
		local encoded = AbiCodec.encode("0x3e8", "core::integer::u256", tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, "core::integer::u256", tm)
		expect((decoded :: any).low):toBe("0x3e8")
		expect((decoded :: any).high):toBe("0x0")
	end)

	it("round-trips struct", function()
		local tm = typeMapWithStruct("mymod::Point", {
			{ name = "x", type = "core::felt252" },
			{ name = "y", type = "core::felt252" },
		})
		local encoded = AbiCodec.encode({ x = "0x1", y = "0x2" }, "mymod::Point", tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, "mymod::Point", tm)
		expect((decoded :: any).x):toBe("0x1")
		expect((decoded :: any).y):toBe("0x2")
	end)

	it("round-trips Array<felt>", function()
		local tm = builtinTypeMap()
		local typeName = "core::array::Array::<core::felt252>"
		local encoded = AbiCodec.encode({ "0xa", "0xb", "0xc" }, typeName, tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, typeName, tm)
		local arr = decoded :: { any }
		expect(#arr):toBe(3)
		expect(arr[1]):toBe("0xa")
		expect(arr[2]):toBe("0xb")
		expect(arr[3]):toBe("0xc")
	end)

	it("round-trips Option Some", function()
		local tm = builtinTypeMap()
		local typeName = "core::option::Option::<core::felt252>"
		local encoded = AbiCodec.encode({ Some = "0x42" }, typeName, tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, typeName, tm)
		expect((decoded :: any).variant):toBe("Some")
		expect((decoded :: any).value):toBe("0x42")
	end)

	it("round-trips Option None", function()
		local tm = builtinTypeMap()
		local typeName = "core::option::Option::<core::felt252>"
		local encoded = AbiCodec.encode({ None = true }, typeName, tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, typeName, tm)
		expect((decoded :: any).variant):toBe("None")
	end)

	it("round-trips ByteArray", function()
		local tm = builtinTypeMap()
		local typeName = "core::byte_array::ByteArray"
		local encoded = AbiCodec.encode("Hello, Starknet!", typeName, tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, typeName, tm)
		expect(decoded):toBe("Hello, Starknet!")
	end)
end)

--------------------------------------------------------------------------------
-- nested types
--------------------------------------------------------------------------------

describe("AbiCodec - nested types", function()
	it("encodes struct containing array", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Batch",
				members = {
					{ name = "id", type = "core::felt252" },
					{ name = "items", type = "core::array::Array::<core::felt252>" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode({
			id = "0x1",
			items = { "0xa", "0xb" },
		}, "mymod::Batch", tm)
		expect(#r):toBe(4) -- id + array(len + 2 elements)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x2") -- array length
		expect(r[3]):toBe("0xa")
		expect(r[4]):toBe("0xb")
	end)

	it("encodes array of enums", function()
		local abi: { any } = {
			{
				type = "enum",
				name = "mymod::Status",
				variants = {
					{ name = "Active", type = "()" },
					{ name = "Paused", type = "()" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode(
			{
				{ variant = "Active", value = nil },
				{ variant = "Paused", value = nil },
			},
			"core::array::Array::<mymod::Status>",
			tm
		)
		expect(#r):toBe(3) -- len + 2 variant indices
		expect(r[1]):toBe("0x2")
		expect(r[2]):toBe("0x0") -- Active
		expect(r[3]):toBe("0x1") -- Paused
	end)

	it("encodes Option of struct", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Pair",
				members = {
					{ name = "a", type = "core::felt252" },
					{ name = "b", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode(
			{ Some = { a = "0x1", b = "0x2" } },
			"core::option::Option::<mymod::Pair>",
			tm
		)
		expect(#r):toBe(3)
		expect(r[1]):toBe("0x0") -- Some
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
	end)

	it("encodes array of tuples", function()
		local tm = builtinTypeMap()
		local r = AbiCodec.encode(
			{
				{ "0x1", "0x2" },
				{ "0x3", "0x4" },
			},
			"core::array::Array::<(core::felt252, core::felt252)>",
			tm
		)
		expect(#r):toBe(5) -- len + 2*2
		expect(r[1]):toBe("0x2")
		expect(r[2]):toBe("0x1")
		expect(r[3]):toBe("0x2")
		expect(r[4]):toBe("0x3")
		expect(r[5]):toBe("0x4")
	end)

	it("encodes struct with ByteArray", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Named",
				members = {
					{ name = "id", type = "core::felt252" },
					{ name = "name", type = "core::byte_array::ByteArray" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local r = AbiCodec.encode({
			id = "0x1",
			name = "Alice",
		}, "mymod::Named", tm)
		-- id(1) + bytearray(0 chunks + pending "Alice" + len)
		expect(#r):toBe(4)
		expect(r[1]):toBe("0x1")
		expect(r[2]):toBe("0x0") -- 0 chunks
		expect(r[3]):toBe("0x416c696365") -- "Alice"
		expect(r[4]):toBe("0x5") -- pending len
	end)

	it("round-trips struct containing array", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Batch",
				members = {
					{ name = "id", type = "core::felt252" },
					{ name = "items", type = "core::array::Array::<core::felt252>" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local original = { id = "0x1", items = { "0xa", "0xb" } }
		local encoded = AbiCodec.encode(original, "mymod::Batch", tm)
		local decoded, _ = AbiCodec.decode(encoded, 1, "mymod::Batch", tm)
		expect((decoded :: any).id):toBe("0x1")
		expect(#(decoded :: any).items):toBe(2)
		expect((decoded :: any).items[1]):toBe("0xa")
		expect((decoded :: any).items[2]):toBe("0xb")
	end)
end)

--------------------------------------------------------------------------------
-- edge cases
--------------------------------------------------------------------------------

describe("AbiCodec - edge cases", function()
	it("handles deeply nested types (3 levels)", function()
		local abi: { any } = {
			{
				type = "struct",
				name = "mymod::Inner",
				members = { { name = "val", type = "core::felt252" } },
			},
			{
				type = "struct",
				name = "mymod::Mid",
				members = { { name = "inner", type = "mymod::Inner" } },
			},
			{
				type = "struct",
				name = "mymod::Outer",
				members = { { name = "mid", type = "mymod::Mid" } },
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		local encoded = AbiCodec.encode({ mid = { inner = { val = "0x42" } } }, "mymod::Outer", tm)
		expect(#encoded):toBe(1)
		expect(encoded[1]):toBe("0x42")

		local decoded, _ = AbiCodec.decode(encoded, 1, "mymod::Outer", tm)
		expect((decoded :: any).mid.inner.val):toBe("0x42")
	end)

	it("handles empty struct (0 members)", function()
		local tm = typeMapWithStruct("mymod::Empty", {})
		local encoded = AbiCodec.encode({}, "mymod::Empty", tm)
		expect(#encoded):toBe(0)

		local decoded, consumed = AbiCodec.decode({}, 1, "mymod::Empty", tm)
		expect(decoded):toBeTruthy() -- empty table
		expect(consumed):toBe(0)
	end)

	it("handles enum with all unit variants", function()
		local tm = typeMapWithEnum("mymod::Direction", {
			{ name = "Up", type = "()" },
			{ name = "Down", type = "()" },
			{ name = "Left", type = "()" },
			{ name = "Right", type = "()" },
		})

		for i, name in { "Up", "Down", "Left", "Right" } do
			local encoded = AbiCodec.encode({ variant = name, value = nil }, "mymod::Direction", tm)
			expect(#encoded):toBe(1)
			expect(encoded[1]):toBe(string.format("0x%x", i - 1))
		end
	end)

	it("handles array of arrays", function()
		local tm = builtinTypeMap()
		local typeName = "core::array::Array::<core::array::Array::<core::felt252>>"
		local input = {
			{ "0x1", "0x2" },
			{ "0x3" },
		}
		local encoded = AbiCodec.encode(input, typeName, tm)
		-- outer_len(2) + inner1_len(2) + 0x1 + 0x2 + inner2_len(1) + 0x3 = 6
		expect(#encoded):toBe(6)
		expect(encoded[1]):toBe("0x2") -- outer len
		expect(encoded[2]):toBe("0x2") -- inner1 len
		expect(encoded[3]):toBe("0x1")
		expect(encoded[4]):toBe("0x2")
		expect(encoded[5]):toBe("0x1") -- inner2 len
		expect(encoded[6]):toBe("0x3")

		-- Round-trip
		local decoded, consumed = AbiCodec.decode(encoded, 1, typeName, tm)
		local arr = decoded :: { any }
		expect(#arr):toBe(2)
		expect(#arr[1]):toBe(2)
		expect(arr[1][1]):toBe("0x1")
		expect(arr[1][2]):toBe("0x2")
		expect(#arr[2]):toBe(1)
		expect(arr[2][1]):toBe("0x3")
		expect(consumed):toBe(6)
	end)

	it("decodes at non-1 offset", function()
		local tm = builtinTypeMap()
		-- Skip first felt, decode second
		local val, consumed = AbiCodec.decode({ "0xfff", "0x42" }, 2, "core::felt252", tm)
		expect(val):toBe("0x42")
		expect(consumed):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- interface function extraction (integration with Contract)
--------------------------------------------------------------------------------

describe("AbiCodec - interface function extraction via buildTypeMap", function()
	it("buildTypeMap handles interface entries without error", function()
		local abi: { any } = {
			{
				type = "interface",
				name = "mymod::IMyContract",
				items = {
					{
						type = "function",
						name = "get_balance",
						inputs = { { name = "account", type = "core::felt252" } },
						outputs = { { name = "balance", type = "core::integer::u256" } },
						state_mutability = "view",
					},
				},
			},
			{
				type = "struct",
				name = "mymod::Point",
				members = {
					{ name = "x", type = "core::felt252" },
					{ name = "y", type = "core::felt252" },
				},
			},
		}
		local tm = AbiCodec.buildTypeMap(abi)
		-- Interface is not a struct/enum, should be ignored by buildTypeMap
		-- But struct should be parsed
		expect(tm["mymod::Point"]):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- encodeInputs / decodeOutputs convenience functions
--------------------------------------------------------------------------------

describe("AbiCodec.encodeInputs", function()
	it("encodes multiple inputs", function()
		local tm = builtinTypeMap()
		local inputs = {
			{ name = "addr", type = "core::felt252" },
			{ name = "amount", type = "core::integer::u256" },
			{ name = "flag", type = "core::bool" },
		}
		local calldata = AbiCodec.encodeInputs({ "0xabc", "0x3e8", true }, inputs, tm)
		expect(#calldata):toBe(4) -- 1 + 2 + 1
		expect(calldata[1]):toBe("0xabc")
		expect(calldata[2]):toBe("0x3e8")
		expect(calldata[3]):toBe("0x0")
		expect(calldata[4]):toBe("0x1")
	end)

	it("encodes empty inputs", function()
		local tm = builtinTypeMap()
		local calldata = AbiCodec.encodeInputs({}, {}, tm)
		expect(#calldata):toBe(0)
	end)
end)

describe("AbiCodec.decodeOutputs", function()
	it("decodes single output directly", function()
		local tm = builtinTypeMap()
		local outputs = { { name = "value", type = "core::felt252" } }
		local result = AbiCodec.decodeOutputs({ "0x42" }, outputs, tm)
		expect(result):toBe("0x42")
	end)

	it("decodes multiple outputs into named table", function()
		local tm = builtinTypeMap()
		local outputs = {
			{ name = "addr", type = "core::felt252" },
			{ name = "amount", type = "core::integer::u256" },
		}
		local result = AbiCodec.decodeOutputs({ "0xabc", "0x3e8", "0x0" }, outputs, tm)
		expect((result :: any).addr):toBe("0xabc")
		expect((result :: any).amount.low):toBe("0x3e8")
	end)

	it("returns raw results for no outputs", function()
		local tm = builtinTypeMap()
		local result = AbiCodec.decodeOutputs({ "0x1", "0x2" }, {}, tm)
		expect(#(result :: { any })):toBe(2)
	end)
end)

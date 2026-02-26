--!strict
local TypedData = require("../../src/wallet/TypedData")

--------------------------------------------------------------------------------
-- Test fixtures
--------------------------------------------------------------------------------

local exampleAddress = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"

-- baseExample.json (LEGACY)
local typedDataExample = {
	types = {
		StarkNetDomain = {
			{ name = "name", type = "felt" },
			{ name = "version", type = "felt" },
			{ name = "chainId", type = "felt" },
		},
		Person = {
			{ name = "name", type = "felt" },
			{ name = "wallet", type = "felt" },
		},
		Mail = {
			{ name = "from", type = "Person" },
			{ name = "to", type = "Person" },
			{ name = "contents", type = "felt" },
		},
	},
	primaryType = "Mail",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = 1,
	},
	message = {
		from = {
			name = "Cow",
			wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
		},
		to = {
			name = "Bob",
			wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
		},
		contents = "Hello, Bob!",
	},
}

-- mail_StructArray.json (LEGACY)
local typedDataStructArrayExample = {
	types = {
		StarkNetDomain = {
			{ name = "name", type = "felt" },
			{ name = "version", type = "felt" },
			{ name = "chainId", type = "felt" },
		},
		Person = {
			{ name = "name", type = "felt" },
			{ name = "wallet", type = "felt" },
		},
		Post = {
			{ name = "title", type = "felt" },
			{ name = "content", type = "felt" },
		},
		Mail = {
			{ name = "from", type = "Person" },
			{ name = "to", type = "Person" },
			{ name = "posts_len", type = "felt" },
			{ name = "posts", type = "Post*" },
		},
	},
	primaryType = "Mail",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = 1,
	},
	message = {
		from = {
			name = "Cow",
			wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
		},
		to = {
			name = "Bob",
			wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
		},
		posts_len = 2,
		posts = {
			{ title = "Greeting", content = "Hello, Bob!" },
			{ title = "Farewell", content = "Goodbye, Bob!" },
		},
	},
}

-- example_baseTypes.json (ACTIVE)
local exampleBaseTypes = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		Example = {
			{ name = "n0", type = "felt" },
			{ name = "n1", type = "bool" },
			{ name = "n2", type = "string" },
			{ name = "n3", type = "selector" },
			{ name = "n4", type = "u128" },
			{ name = "n5", type = "i128" },
			{ name = "n6", type = "ContractAddress" },
			{ name = "n7", type = "ClassHash" },
			{ name = "n8", type = "timestamp" },
			{ name = "n9", type = "shortstring" },
		},
	},
	primaryType = "Example",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = "1",
		revision = "1",
	},
	message = {
		n0 = "0x3e8",
		n1 = true,
		n2 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
		n3 = "transfer",
		n4 = 10,
		n5 = -10,
		n6 = "0x3e8",
		n7 = "0x3e8",
		n8 = 1000,
		n9 = "transfer",
	},
}

-- example_presetTypes.json (ACTIVE)
local examplePresetTypes = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		Example = {
			{ name = "n0", type = "TokenAmount" },
			{ name = "n1", type = "NftId" },
		},
	},
	primaryType = "Example",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = "1",
		revision = "1",
	},
	message = {
		n0 = {
			token_address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			amount = {
				low = "0x3e8",
				high = "0x0",
			},
		},
		n1 = {
			collection_address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			token_id = {
				low = "0x3e8",
				high = "0x0",
			},
		},
	},
}

-- example_enum.json (ACTIVE)
local exampleEnum = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		Example = {
			{ name = "someEnum1", type = "enum", contains = "EnumA" },
			{ name = "someEnum2", type = "enum", contains = "EnumB" },
		},
		EnumA = {
			{ name = "Variant 1", type = "()" },
			{ name = "Variant 2", type = "(u128,u128*)" },
			{ name = "Variant 3", type = "(u128)" },
		},
		EnumB = {
			{ name = "Variant 1", type = "()" },
			{ name = "Variant 2", type = "(u128)" },
		},
	},
	primaryType = "Example",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = "1",
		revision = "1",
	},
	message = {
		someEnum1 = {
			["Variant 2"] = { 2, { 0, 1 } },
		},
		someEnum2 = {
			["Variant 1"] = {},
		},
	},
}

-- example_enumNested.json (ACTIVE)
local exampleEnumNested = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		Example = { { name = "someEnum", type = "enum", contains = "EnumA" } },
		EnumA = {
			{ name = "Variant 1", type = "()" },
			{ name = "Variant 2", type = "(u128,StructA)" },
		},
		StructA = { { name = "nestedEnum", type = "enum", contains = "EnumB" } },
		EnumB = {
			{ name = "Variant A", type = "()" },
			{ name = "Variant B", type = "(StructB*)" },
		},
		StructB = { { name = "flag", type = "bool" } },
	},
	primaryType = "Example",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = "1",
		revision = "1",
	},
	message = {
		someEnum = {
			["Variant 2"] = { 2, { nestedEnum = { ["Variant B"] = { { { flag = true }, { flag = false } } } } } },
		},
	},
}

-- session_MerkleTree.json (LEGACY)
local typedDataSessionExample = {
	primaryType = "Session",
	types = {
		Policy = {
			{ name = "contractAddress", type = "felt" },
			{ name = "selector", type = "selector" },
		},
		Session = {
			{ name = "key", type = "felt" },
			{ name = "expires", type = "felt" },
			{ name = "root", type = "merkletree", contains = "Policy" },
		},
		StarkNetDomain = {
			{ name = "name", type = "felt" },
			{ name = "version", type = "felt" },
			{ name = "chain_id", type = "felt" },
		},
	},
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chain_id = 1,
	},
	message = {
		key = "0x0000000000000000000000000000000000000000000000000000000000000000",
		expires = "0x0000000000000000000000000000000000000000000000000000000000000000",
		root = {
			{ contractAddress = "0x1", selector = "transfer" },
			{ contractAddress = "0x2", selector = "transfer" },
			{ contractAddress = "0x3", selector = "transfer" },
		},
	},
}

-- typedDataStringExample (LEGACY) - inline definition matching starknet.js test
-- stringToStringStruct: each character's ASCII code as a hex felt
local function stringToStringStruct(str: string): { len: number, data: { string } }
	local data: { string } = {}
	for i = 1, #str do
		table.insert(data, string.format("0x%x", string.byte(str, i)))
	end
	return { len = #str, data = data }
end

local typedDataStringExample = {
	types = {
		StarkNetDomain = {
			{ name = "name", type = "felt" },
			{ name = "version", type = "felt" },
			{ name = "chainId", type = "felt" },
		},
		Person = {
			{ name = "name", type = "felt" },
			{ name = "wallet", type = "felt" },
		},
		String = {
			{ name = "len", type = "felt" },
			{ name = "data", type = "felt*" },
		},
		Mail = {
			{ name = "from", type = "Person" },
			{ name = "to", type = "Person" },
			{ name = "contents", type = "String" },
		},
	},
	primaryType = "Mail",
	domain = {
		name = "StarkNet Mail",
		version = "1",
		chainId = 1,
	},
	message = {
		from = {
			name = "Cow",
			wallet = exampleAddress,
		},
		to = {
			name = "Bob",
			wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
		},
		contents = stringToStringStruct(
			"this is way longer than just 32 characters, to test if that is possible within a typedData struct."
		),
	},
}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("TypedData identifyRevision", function()
	it("detects LEGACY revision from StarkNetDomain", function()
		local rev = TypedData.identifyRevision(typedDataExample)
		expect(rev):toBe("0")
	end)

	it("detects ACTIVE revision from StarknetDomain with revision 1", function()
		local rev = TypedData.identifyRevision(exampleBaseTypes)
		expect(rev):toBe("1")
	end)

	it("handles numeric revision value", function()
		local data = {
			types = { StarknetDomain = exampleBaseTypes.types.StarknetDomain },
			domain = { name = "test", version = "1", chainId = "1", revision = 1 },
			primaryType = "Example",
			message = {},
		}
		local rev = TypedData.identifyRevision(data)
		expect(rev):toBe("1")
	end)
end)

describe("TypedData encodeType", function()
	it("encodes Mail type (LEGACY)", function()
		local encoded = TypedData.encodeType(typedDataExample.types, "Mail")
		expect(encoded):toBe("Mail(from:Person,to:Person,contents:felt)Person(name:felt,wallet:felt)")
	end)

	it("encodes Mail with struct array (LEGACY)", function()
		local encoded = TypedData.encodeType(typedDataStructArrayExample.types, "Mail")
		expect(encoded):toBe(
			"Mail(from:Person,to:Person,posts_len:felt,posts:Post*)Person(name:felt,wallet:felt)Post(title:felt,content:felt)"
		)
	end)

	it("encodes Mail type (ACTIVE)", function()
		local encoded = TypedData.encodeType(typedDataExample.types, "Mail", "1")
		expect(encoded):toBe(
			'"Mail"("from":"Person","to":"Person","contents":"felt")"Person"("name":"felt","wallet":"felt")'
		)
	end)

	it("encodes Mail with struct array (ACTIVE)", function()
		local encoded = TypedData.encodeType(typedDataStructArrayExample.types, "Mail", "1")
		expect(encoded):toBe(
			'"Mail"("from":"Person","to":"Person","posts_len":"felt","posts":"Post*")"Person"("name":"felt","wallet":"felt")"Post"("title":"felt","content":"felt")'
		)
	end)

	it("encodes Example with base types (ACTIVE)", function()
		local encoded = TypedData.encodeType(exampleBaseTypes.types, "Example", "1")
		expect(encoded):toBe(
			'"Example"("n0":"felt","n1":"bool","n2":"string","n3":"selector","n4":"u128","n5":"i128","n6":"ContractAddress","n7":"ClassHash","n8":"timestamp","n9":"shortstring")'
		)
	end)

	it("encodes Example with preset types (ACTIVE)", function()
		local encoded = TypedData.encodeType(examplePresetTypes.types, "Example", "1")
		expect(encoded):toBe(
			'"Example"("n0":"TokenAmount","n1":"NftId")"NftId"("collection_address":"ContractAddress","token_id":"u256")"TokenAmount"("token_address":"ContractAddress","amount":"u256")"u256"("low":"u128","high":"u128")'
		)
	end)

	it("encodes Example with enums (ACTIVE)", function()
		local encoded = TypedData.encodeType(exampleEnum.types, "Example", "1")
		expect(encoded):toBe(
			'"Example"("someEnum1":"EnumA","someEnum2":"EnumB")"EnumA"("Variant 1":(),"Variant 2":("u128","u128*"),"Variant 3":("u128"))"EnumB"("Variant 1":(),"Variant 2":("u128"))'
		)
	end)

	it("encodes Example with nested enums (ACTIVE)", function()
		local encoded = TypedData.encodeType(exampleEnumNested.types, "Example", "1")
		expect(encoded):toBe(
			'"Example"("someEnum":"EnumA")"EnumA"("Variant 1":(),"Variant 2":("u128","StructA"))"EnumB"("Variant A":(),"Variant B":("StructB*"))"StructA"("nestedEnum":"EnumB")"StructB"("flag":"bool")'
		)
	end)
end)

describe("TypedData getTypeHash", function()
	it("hashes StarkNetDomain (LEGACY)", function()
		local hash = TypedData.getTypeHash(typedDataExample.types, "StarkNetDomain")
		expect(hash):toBe("0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288")
	end)

	it("hashes Person (LEGACY)", function()
		local hash = TypedData.getTypeHash(typedDataExample.types, "Person")
		expect(hash):toBe("0x2896dbe4b96a67110f454c01e5336edc5bbc3635537efd690f122f4809cc855")
	end)

	it("hashes Mail (LEGACY)", function()
		local hash = TypedData.getTypeHash(typedDataExample.types, "Mail")
		expect(hash):toBe("0x13d89452df9512bf750f539ba3001b945576243288137ddb6c788457d4b2f79")
	end)

	it("hashes Post (LEGACY)", function()
		local hash = TypedData.getTypeHash(typedDataStructArrayExample.types, "Post")
		expect(hash):toBe("0x1d71e69bf476486b43cdcfaf5a85c00bb2d954c042b281040e513080388356d")
	end)

	it("hashes Mail with struct array (LEGACY)", function()
		local hash = TypedData.getTypeHash(typedDataStructArrayExample.types, "Mail")
		expect(hash):toBe("0x873b878e35e258fc99e3085d5aaad3a81a0c821f189c08b30def2cde55ff27")
	end)

	it("hashes Example base types (ACTIVE)", function()
		local hash = TypedData.getTypeHash(exampleBaseTypes.types, "Example", "1")
		expect(hash):toBe("0x1f94cd0be8b4097a41486170fdf09a4cd23aefbc74bb2344718562994c2c111")
	end)

	it("hashes Example preset types (ACTIVE)", function()
		local hash = TypedData.getTypeHash(examplePresetTypes.types, "Example", "1")
		expect(hash):toBe("0x1a25a8bb84b761090b1fadaebe762c4b679b0d8883d2bedda695ea340839a55")
	end)

	it("hashes Example enum (ACTIVE)", function()
		local hash = TypedData.getTypeHash(exampleEnum.types, "Example", "1")
		expect(hash):toBe("0x8eb4aeac64b707f3e843284c4258df6df1f0f7fd38dcffdd8a153a495cd351")
	end)

	it("hashes Example enum nested (ACTIVE)", function()
		local hash = TypedData.getTypeHash(exampleEnumNested.types, "Example", "1")
		expect(hash):toBe("0x2143bb787fabace39d62e9acf8b6e97d9a369000516c3e6ffd963dc1370fc1a")
	end)
end)

describe("TypedData encodeValue", function()
	it("encodes selector type", function()
		local _, encoded = TypedData.encodeValue({}, "selector", "transfer", nil, "0")
		expect(encoded):toBe("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e")
	end)

	it("encodes selector passthrough for hex", function()
		local _, encoded = TypedData.encodeValue(
			{},
			"selector",
			"0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e",
			nil,
			"0"
		)
		expect(encoded):toBe("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e")
	end)

	it("encodes felt type", function()
		local _, encoded = TypedData.encodeValue({}, "felt", "0x3e8", nil, "0")
		expect(encoded):toBe("0x3e8")
	end)

	it("encodes bool type", function()
		local _, encoded1 = TypedData.encodeValue({}, "bool", true, nil, "1")
		expect(encoded1):toBe("0x1")

		local _, encoded0 = TypedData.encodeValue({}, "bool", false, nil, "1")
		expect(encoded0):toBe("0x0")
	end)

	it("encodes shortstring type", function()
		local _, encoded = TypedData.encodeValue({}, "shortstring", "transfer", nil, "1")
		expect(encoded):toBeTruthy()
	end)
end)

describe("TypedData getStructHash", function()
	it("hashes StarkNetDomain (LEGACY)", function()
		local hash = TypedData.getStructHash(typedDataExample.types, "StarkNetDomain", typedDataExample.domain, "0")
		expect(hash):toBe("0x54833b121883a3e3aebff48ec08a962f5742e5f7b973469c1f8f4f55d470b07")
	end)

	it("hashes StarknetDomain (ACTIVE)", function()
		local hash =
			TypedData.getStructHash(exampleBaseTypes.types, "StarknetDomain", exampleBaseTypes.domain, "1")
		expect(hash):toBe("0x555f72e550b308e50c1a4f8611483a174026c982a9893a05c185eeb85399657")
	end)
end)

describe("TypedData merkle tree", function()
	it("computes merkle root for simple leaves", function()
		local StarkField = require("../../src/crypto/StarkField")
		local Pedersen = require("../../src/crypto/Pedersen")
		local root = TypedData.merkleRoot({ "0x1", "0x2", "0x3" }, function(a: string, b: string): string
			return StarkField.toHex(Pedersen.hash(StarkField.fromHex(a), StarkField.fromHex(b)))
		end)
		expect(root):toBe("0x15ac9e457789ef0c56e5d559809e7336a909c14ee2511503fa7af69be1ba639")
	end)

	it("computes merkle root for custom types (Policy)", function()
		local leaves = {
			{ contractAddress = "0x1", selector = "transfer" },
			{ contractAddress = "0x2", selector = "transfer" },
			{ contractAddress = "0x3", selector = "transfer" },
		}

		-- Hash each leaf as a Policy struct
		local types = {
			Policy = {
				{ name = "contractAddress", type = "felt" },
				{ name = "selector", type = "selector" },
			},
		}
		local hashedLeaves: { string } = {}
		for _, leaf in leaves do
			local _, encoded = TypedData.encodeValue(types, "Policy", leaf, nil, "0")
			table.insert(hashedLeaves, encoded)
		end

		-- Build merkle tree from hashed leaves
		local StarkField = require("../../src/crypto/StarkField")
		local Pedersen = require("../../src/crypto/Pedersen")
		local root = TypedData.merkleRoot(hashedLeaves, function(a: string, b: string): string
			return StarkField.toHex(Pedersen.hash(StarkField.fromHex(a), StarkField.fromHex(b)))
		end)
		expect(root):toBe("0x12354b159e3799dc0ebe86d62dde4ce7b300538d471e5a7fef23dcbac076011")
	end)
end)

describe("TypedData getMessageHash", function()
	it("hashes baseExample (LEGACY)", function()
		local hash = TypedData.getMessageHash(typedDataExample, exampleAddress)
		expect(hash):toBe("0x6fcff244f63e38b9d88b9e3378d44757710d1b244282b435cb472053c8d78d0")
	end)

	it("hashes mail_StructArray (LEGACY)", function()
		local hash = TypedData.getMessageHash(typedDataStructArrayExample, exampleAddress)
		expect(hash):toBe("0x5914ed2764eca2e6a41eb037feefd3d2e33d9af6225a9e7fe31ac943ff712c")
	end)

	it("hashes string example (LEGACY)", function()
		local hash = TypedData.getMessageHash(typedDataStringExample, exampleAddress)
		expect(hash):toBe("0x70338fb11b8f70b68b261de8a322bcb004bd85e88ac47d9147982c7f5ac66fd")
	end)

	it("hashes session_MerkleTree (LEGACY)", function()
		local hash = TypedData.getMessageHash(typedDataSessionExample, exampleAddress)
		expect(hash):toBe("0x751fb7d98545f7649d0d0eadc80d770fcd88d8cfaa55590b284f4e1b701ef0a")
	end)

	it("hashes example_baseTypes (ACTIVE)", function()
		local hash = TypedData.getMessageHash(exampleBaseTypes, exampleAddress)
		expect(hash):toBe("0xdb7829db8909c0c5496f5952bcfc4fc894341ce01842537fc4f448743480b6")
	end)

	it("hashes example_presetTypes (ACTIVE)", function()
		local hash = TypedData.getMessageHash(examplePresetTypes, exampleAddress)
		expect(hash):toBe("0x185b339d5c566a883561a88fb36da301051e2c0225deb325c91bb7aa2f3473a")
	end)

	it("hashes example_enum (ACTIVE)", function()
		local hash = TypedData.getMessageHash(exampleEnum, exampleAddress)
		expect(hash):toBe("0x6e61abaf480b1370bbf231f54e298c5f4872f40a6d2dd409ff30accee5bbd1e")
	end)

	it("hashes example_enumNested (ACTIVE)", function()
		local hash = TypedData.getMessageHash(exampleEnumNested, exampleAddress)
		expect(hash):toBe("0x691fc54567306a8ea5431130f1b98299e74a748ac391540a86736f20ef5f2b7")
	end)

	it("handles numeric revision (Braavos compat)", function()
		local data = {
			types = exampleBaseTypes.types,
			primaryType = exampleBaseTypes.primaryType,
			domain = {
				name = exampleBaseTypes.domain.name,
				version = exampleBaseTypes.domain.version,
				chainId = exampleBaseTypes.domain.chainId,
				revision = 1,
			},
			message = exampleBaseTypes.message,
		}
		local hash = TypedData.getMessageHash(data, exampleAddress)
		expect(hash):toBe("0xdb7829db8909c0c5496f5952bcfc4fc894341ce01842537fc4f448743480b6")
	end)
end)

describe("TypedData Account integration", function()
	it("hashMessage returns correct hash", function()
		local StarkSigner = require("../../src/signer/StarkSigner")
		local RpcProvider = require("../../src/provider/RpcProvider")
		local Account = require("../../src/wallet/Account")
		local MockPromise = require("../helpers/MockPromise")

		local function mockHttp(_url: string, _method: string, _body: string?): (number, string)
			return 200, '{"jsonrpc":"2.0","id":1,"result":"0x0"}'
		end
		local provider = RpcProvider.new({
			nodeUrl = "https://mock.example.com",
			_httpRequest = mockHttp,
			_Promise = MockPromise,
		})

		local privKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
		local signer = StarkSigner.new(privKey)
		local account = Account.new({
			address = exampleAddress,
			signer = signer,
			provider = provider,
		})

		local hash = account:hashMessage(typedDataExample)
		expect(hash):toBe("0x6fcff244f63e38b9d88b9e3378d44757710d1b244282b435cb472053c8d78d0")
	end)

	it("signMessage returns valid signature", function()
		local BigInt = require("../../src/crypto/BigInt")
		local StarkSigner = require("../../src/signer/StarkSigner")
		local ECDSA = require("../../src/crypto/ECDSA")
		local RpcProvider = require("../../src/provider/RpcProvider")
		local Account = require("../../src/wallet/Account")
		local MockPromise = require("../helpers/MockPromise")

		local function mockHttp(_url: string, _method: string, _body: string?): (number, string)
			return 200, '{"jsonrpc":"2.0","id":1,"result":"0x0"}'
		end
		local provider = RpcProvider.new({
			nodeUrl = "https://mock.example.com",
			_httpRequest = mockHttp,
			_Promise = MockPromise,
		})

		local privKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
		local signer = StarkSigner.new(privKey)
		local account = Account.new({
			address = exampleAddress,
			signer = signer,
			provider = provider,
		})

		local sig = account:signMessage(typedDataExample)
		expect(#sig):toBe(2)
		-- Verify the signature
		local hash = account:hashMessage(typedDataExample)
		local msgBuf = BigInt.fromHex(hash)
		local pubKey = signer:getPubKey()
		local sigObj = { r = BigInt.fromHex(sig[1]), s = BigInt.fromHex(sig[2]) }
		local valid = ECDSA.verify(msgBuf, pubKey, sigObj)
		expect(valid):toBe(true)
	end)

	it("signMessage for ACTIVE revision", function()
		local BigInt = require("../../src/crypto/BigInt")
		local StarkSigner = require("../../src/signer/StarkSigner")
		local ECDSA = require("../../src/crypto/ECDSA")
		local RpcProvider = require("../../src/provider/RpcProvider")
		local Account = require("../../src/wallet/Account")
		local MockPromise = require("../helpers/MockPromise")

		local function mockHttp(_url: string, _method: string, _body: string?): (number, string)
			return 200, '{"jsonrpc":"2.0","id":1,"result":"0x0"}'
		end
		local provider = RpcProvider.new({
			nodeUrl = "https://mock.example.com",
			_httpRequest = mockHttp,
			_Promise = MockPromise,
		})

		local privKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
		local signer = StarkSigner.new(privKey)
		local account = Account.new({
			address = exampleAddress,
			signer = signer,
			provider = provider,
		})

		local sig = account:signMessage(exampleBaseTypes)
		expect(#sig):toBe(2)
		-- Verify the signature
		local hash = account:hashMessage(exampleBaseTypes)
		local msgBuf = BigInt.fromHex(hash)
		local pubKey = signer:getPubKey()
		local sigObj = { r = BigInt.fromHex(sig[1]), s = BigInt.fromHex(sig[2]) }
		local valid = ECDSA.verify(msgBuf, pubKey, sigObj)
		expect(valid):toBe(true)
	end)
end)

describe("TypedData edge cases", function()
	it("encodes empty type gracefully", function()
		local encoded = TypedData.encodeType({}, "NonExistent")
		expect(encoded):toBe("")
	end)

	it("handles i128 negative value", function()
		local _, encoded = TypedData.encodeValue({}, "i128", -10, nil, "1")
		expect(encoded):toBeTruthy()
	end)
end)

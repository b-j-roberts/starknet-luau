--!strict
local ERC721 = require("../../src/contract/ERC721")
local Account = require("../../src/wallet/Account")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local NFT_ADDR = "0x076503062d78f4481be03c9145022d6a4a71ec0719aa07756f79a2384dc7ef16"
local NORMALIZED_NFT_ADDR = "0x76503062d78f4481be03c9145022d6a4a71ec0719aa07756f79a2384dc7ef16"
local OWNER_ADDR = "0x1234567890abcdef1234567890abcdef12345678"
local OPERATOR_ADDR = "0xabcdef1234567890abcdef1234567890abcdef12"
local RECIPIENT_ADDR = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

-- Token IDs as hex (will be encoded as u256 = 2 felts: low, high)
local TOKEN_ID_1 = "0x1"
local TOKEN_ID_42 = "0x2a"

--------------------------------------------------------------------------------
-- Mock RPC layer (shared via TestUtils)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

local function createTestAccount(): any
	rpc.resetHandlers()
	local provider = rpc.createTestProvider()
	return Account.fromPrivateKey({
		privateKey = TestUtils.TEST_PRIVATE_KEY,
		provider = provider,
	})
end

--------------------------------------------------------------------------------
-- ERC721.new (constructor)
--------------------------------------------------------------------------------

describe("ERC721.new - constructor", function()
	it("creates an ERC721 instance with address and provider", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local nft = ERC721.new(NFT_ADDR, provider)
		expect(nft):toBeTruthy()
		expect(nft.address):toBe(NORMALIZED_NFT_ADDR)
	end)

	it("creates an ERC721 instance with optional account", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()

		local nft = ERC721.new(NFT_ADDR, provider, account)
		expect(nft):toBeTruthy()
		expect(nft.address):toBe(NORMALIZED_NFT_ADDR)
	end)

	it("errors when address is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		expect(function()
			ERC721.new(nil :: any, provider)
		end):toThrow()
	end)

	it("errors when provider is missing", function()
		expect(function()
			ERC721.new(NFT_ADDR, nil :: any)
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- ERC721.getAbi
--------------------------------------------------------------------------------

describe("ERC721.getAbi - built-in ABI", function()
	it("returns the ERC-721 ABI", function()
		local abi = ERC721.getAbi()
		expect(#abi > 0):toBe(true)
	end)

	it("contains standard ERC-721 snake_case functions", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		expect(nft:hasFunction("name")):toBe(true)
		expect(nft:hasFunction("symbol")):toBe(true)
		expect(nft:hasFunction("balance_of")):toBe(true)
		expect(nft:hasFunction("owner_of")):toBe(true)
		expect(nft:hasFunction("get_approved")):toBe(true)
		expect(nft:hasFunction("is_approved_for_all")):toBe(true)
		expect(nft:hasFunction("transfer_from")):toBe(true)
		expect(nft:hasFunction("approve")):toBe(true)
		expect(nft:hasFunction("set_approval_for_all")):toBe(true)
	end)

	it("contains camelCase aliases", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		expect(nft:hasFunction("balanceOf")):toBe(true)
		expect(nft:hasFunction("ownerOf")):toBe(true)
		expect(nft:hasFunction("getApproved")):toBe(true)
		expect(nft:hasFunction("isApprovedForAll")):toBe(true)
		expect(nft:hasFunction("transferFrom")):toBe(true)
		expect(nft:hasFunction("setApprovalForAll")):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Read methods (view functions)
--------------------------------------------------------------------------------

describe("ERC721 - read methods (view)", function()
	it("name() returns collection name as felt", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4d794e4654" } -- "MyNFT"
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:name():expect()
		expect(result):toBe("0x4d794e4654")
	end)

	it("symbol() returns collection symbol as felt", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4e4654" } -- "NFT"
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:symbol():expect()
		expect(result):toBe("0x4e4654")
	end)

	it("balance_of(owner) returns u256", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3", "0x0" } -- 3 NFTs
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:balance_of(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x3")
		expect((result :: any).high):toBe("0x0")
	end)

	it("balanceOf(owner) camelCase alias works", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3", "0x0" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:balanceOf(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x3")
		expect((result :: any).high):toBe("0x0")
	end)

	it("owner_of(tokenId) returns owner address", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { OWNER_ADDR }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:owner_of(TOKEN_ID_1):expect()
		expect(result):toBe(OWNER_ADDR)
	end)

	it("ownerOf(tokenId) camelCase alias works", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { OWNER_ADDR }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:ownerOf(TOKEN_ID_1):expect()
		expect(result):toBe(OWNER_ADDR)
	end)

	it("get_approved(tokenId) returns approved address", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { OPERATOR_ADDR }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:get_approved(TOKEN_ID_1):expect()
		expect(result):toBe(OPERATOR_ADDR)
	end)

	it("getApproved(tokenId) camelCase alias works", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { OPERATOR_ADDR }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:getApproved(TOKEN_ID_1):expect()
		expect(result):toBe(OPERATOR_ADDR)
	end)

	it("is_approved_for_all(owner, operator) returns true", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1" } -- true
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:is_approved_for_all(OWNER_ADDR, OPERATOR_ADDR):expect()
		expect(result):toBe(true)
	end)

	it("is_approved_for_all(owner, operator) returns false", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" } -- false
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:is_approved_for_all(OWNER_ADDR, OPERATOR_ADDR):expect()
		expect(result):toBe(false)
	end)

	it("isApprovedForAll(owner, operator) camelCase alias works", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:isApprovedForAll(OWNER_ADDR, OPERATOR_ADDR):expect()
		expect(result):toBe(true)
	end)

	it("owner_of sends correct calldata (u256 token_id = 2 felts)", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_call"] = function(_params)
			return { OWNER_ADDR }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		nft:owner_of(TOKEN_ID_42):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				expect(req.contract_address):toBe(NORMALIZED_NFT_ADDR)
				-- u256 token_id = 2 felts (low, high)
				expect(#req.calldata):toBe(2)
			end
		end
		expect(found):toBe(true)
	end)

	it("is_approved_for_all sends correct calldata (2 addresses)", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		nft:is_approved_for_all(OWNER_ADDR, OPERATOR_ADDR):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				expect(#req.calldata):toBe(2)
				expect(req.calldata[1]):toBe(OWNER_ADDR)
				expect(req.calldata[2]):toBe(OPERATOR_ADDR)
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Write methods (external functions)
--------------------------------------------------------------------------------

describe("ERC721 - write methods (external)", function()
	it("transfer_from(from, to, tokenId) returns tx hash", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:transfer_from(OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("transferFrom(from, to, tokenId) camelCase alias works", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:transferFrom(OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("approve(to, tokenId) returns tx hash", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:approve(OPERATOR_ADDR, TOKEN_ID_1):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("set_approval_for_all(operator, approved) returns tx hash", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:set_approval_for_all(OPERATOR_ADDR, true):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("setApprovalForAll(operator, approved) camelCase alias works", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:setApprovalForAll(OPERATOR_ADDR, false):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("transfer_from supports dryRun option", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		local result = nft:transfer_from(OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
	end)

	it("errors when no account for write methods", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider) -- no account

		expect(function()
			nft:transfer_from(OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1)
		end):toThrow()
	end)

	it("transfer_from sends addInvokeTransaction to provider", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider, account)

		nft:transfer_from(OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				found = true
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- populate() for multicall batching
--------------------------------------------------------------------------------

describe("ERC721 - populate for multicall", function()
	it("populate transfer_from returns correct Call object", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local call = nft:populate("transfer_from", { OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_1 })
		expect(call.contractAddress):toBe(NORMALIZED_NFT_ADDR)
		expect(call.entrypoint):toBe("transfer_from")
		-- from (1) + to (1) + u256 token_id (2) = 4
		expect(#call.calldata):toBe(4)
	end)

	it("populate approve returns correct Call object", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local call = nft:populate("approve", { OPERATOR_ADDR, TOKEN_ID_1 })
		expect(call.contractAddress):toBe(NORMALIZED_NFT_ADDR)
		expect(call.entrypoint):toBe("approve")
		-- to (1) + u256 token_id (2) = 3
		expect(#call.calldata):toBe(3)
	end)

	it("populate set_approval_for_all returns correct Call object", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local call = nft:populate("set_approval_for_all", { OPERATOR_ADDR, true })
		expect(call.contractAddress):toBe(NORMALIZED_NFT_ADDR)
		expect(call.entrypoint):toBe("set_approval_for_all")
		-- operator (1) + bool (1) = 2
		expect(#call.calldata):toBe(2)
	end)

	it("can batch multiple ERC721 calls", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local call1 = nft:populate("approve", { OPERATOR_ADDR, TOKEN_ID_1 })
		local call2 = nft:populate("transfer_from", { OWNER_ADDR, RECIPIENT_ADDR, TOKEN_ID_42 })

		expect(call1.contractAddress):toBe(NORMALIZED_NFT_ADDR)
		expect(call2.contractAddress):toBe(NORMALIZED_NFT_ADDR)
		expect(call1.entrypoint):toBe("approve")
		expect(call2.entrypoint):toBe("transfer_from")
	end)
end)

--------------------------------------------------------------------------------
-- Contract utility methods inherited
--------------------------------------------------------------------------------

describe("ERC721 - inherited Contract methods", function()
	it("getFunctions returns all ERC-721 functions", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local fns = nft:getFunctions()
		-- 9 snake_case + 6 camelCase = 15
		expect(#fns):toBe(15)
	end)

	it("getFunction returns parsed metadata for owner_of", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local fn = nft:getFunction("owner_of")
		expect(fn):toBeTruthy()
		expect((fn :: any).stateMutability):toBe("view")
		expect(#(fn :: any).inputs):toBe(1)
	end)

	it("getFunction returns parsed metadata for transfer_from", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local fn = nft:getFunction("transfer_from")
		expect(fn):toBeTruthy()
		expect((fn :: any).stateMutability):toBe("external")
		expect(#(fn :: any).inputs):toBe(3)
	end)

	it("hasFunction returns false for non-ERC721 function", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		expect(nft:hasFunction("mint")):toBe(false)
		expect(nft:hasFunction("burn")):toBe(false)
		expect(nft:hasFunction("totalSupply")):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Edge cases
--------------------------------------------------------------------------------

describe("ERC721 - edge cases", function()
	it("balance_of with zero NFTs returns u256 zero", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x0" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:balance_of(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x0")
		expect((result :: any).high):toBe("0x0")
	end)

	it("owner_of with zero address", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:owner_of(TOKEN_ID_1):expect()
		expect(result):toBe("0x0")
	end)

	it("get_approved returns zero when no approval set", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" }
		end
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		local result = nft:get_approved(TOKEN_ID_1):expect()
		expect(result):toBe("0x0")
	end)

	it("different NFT addresses create separate instances", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local nft1 = ERC721.new("0xaaa", provider)
		local nft2 = ERC721.new("0xbbb", provider)

		expect(nft1.address):toBe("0xaaa")
		expect(nft2.address):toBe("0xbbb")
	end)

	it("large token_id u256 encodes correctly", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { OWNER_ADDR }
		end
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()
		local nft = ERC721.new(NFT_ADDR, provider)

		-- Large token ID
		nft:owner_of("0xffffffffffffffffffffffffffffffff"):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				-- u256 = 2 felts
				expect(#req.calldata):toBe(2)
			end
		end
		expect(found):toBe(true)
	end)
end)

--!strict
-- Cross-reference test: validates ALL crypto primitives against centralized test vectors.
-- This is the single source of truth for starknet.js compatibility.

local BigInt = require("../../src/crypto/BigInt")
local StarkField = require("../../src/crypto/StarkField")
local Poseidon = require("../../src/crypto/Poseidon")
local Pedersen = require("../../src/crypto/Pedersen")
local Keccak = require("../../src/crypto/Keccak")
local StarkCurve = require("../../src/crypto/StarkCurve")
local ECDSA = require("../../src/crypto/ECDSA")
local TransactionHash = require("../../src/tx/TransactionHash")
local Account = require("../../src/wallet/Account")

local TV = require("./test-vectors")

--------------------------------------------------------------------------------
-- BigInt cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: BigInt - addition", function()
	for i, vec in TV.BigInt.add do
		it(`add vector {i}: {vec[1]} + {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local b = BigInt.fromHex(vec[2])
			local result = BigInt.add(a, b)
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: BigInt - subtraction", function()
	for i, vec in TV.BigInt.sub do
		it(`sub vector {i}: {vec[1]} - {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local b = BigInt.fromHex(vec[2])
			local result = BigInt.sub(a, b)
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: BigInt - multiplication", function()
	for i, vec in TV.BigInt.mul do
		it(`mul vector {i}: {vec[1]} * {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local b = BigInt.fromHex(vec[2])
			local result = BigInt.mul(a, b)
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: BigInt - modular arithmetic", function()
	for i, vec in TV.BigInt.modular do
		it(`modular vector {i}: {vec.op}`, function()
			if vec.op == "mod" then
				local a = BigInt.fromHex(vec.a)
				local m = BigInt.fromHex(vec.m)
				local result = BigInt.mod(a, m)
				expect(BigInt.toHex(result)):toBe(vec.expected)
			elseif vec.op == "addmod" then
				local a = BigInt.fromHex(vec.a)
				local b = BigInt.fromHex(vec.b)
				local m = BigInt.fromHex(vec.m)
				local result = BigInt.addmod(a, b, m)
				expect(BigInt.toHex(result)):toBe(vec.expected)
			elseif vec.op == "invmod" then
				local a = BigInt.fromHex(vec.a)
				local m = BigInt.fromHex(vec.m)
				local result = BigInt.invmod(a, m)
				expect(BigInt.toHex(result)):toBe(vec.expected)
			end
		end)
	end
end)

describe("Cross-ref: BigInt - hex round-trip", function()
	for i, hex in TV.BigInt.hexRoundTrip do
		it(`round-trip vector {i}: {hex}`, function()
			local n = BigInt.fromHex(hex)
			expect(BigInt.toHex(n)):toBe(hex)
		end)
	end
end)

describe("Cross-ref: BigInt - comparison", function()
	for i, vec in TV.BigInt.comparison do
		it(`cmp vector {i}: cmp({vec[1]}, {vec[2]}) = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local b = BigInt.fromHex(vec[2])
			local result = BigInt.cmp(a, b)
			if vec[3] == 0 then
				expect(result == 0):toBe(true)
			elseif vec[3] == 1 then
				expect(result > 0):toBe(true)
			else
				expect(result < 0):toBe(true)
			end
		end)
	end
end)

describe("Cross-ref: BigInt - shift left", function()
	for i, vec in TV.BigInt.bitOps.shl do
		it(`shl vector {i}: {vec[1]} << {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local result = BigInt.shl(a, vec[2])
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: BigInt - shift right", function()
	for i, vec in TV.BigInt.bitOps.shr do
		it(`shr vector {i}: {vec[1]} >> {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local result = BigInt.shr(a, vec[2])
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: BigInt - bitwise AND", function()
	for i, vec in TV.BigInt.bitOps.band do
		it(`band vector {i}: {vec[1]} & {vec[2]} = {vec[3]}`, function()
			local a = BigInt.fromHex(vec[1])
			local b = BigInt.fromHex(vec[2])
			local result = BigInt.band(a, b)
			expect(BigInt.toHex(result)):toBe(vec[3])
		end)
	end
end)

--------------------------------------------------------------------------------
-- Poseidon cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: Poseidon - hash(a, b)", function()
	for i, vec in TV.Poseidon.hash do
		it(`hash vector {i}: hash({vec[1]}, {vec[2]})`, function()
			local a = StarkField.fromHex(vec[1])
			local b = StarkField.fromHex(vec[2])
			local result = Poseidon.hash(a, b)
			expect(StarkField.toHex(result)):toBe(vec[3])
		end)
	end
end)

describe("Cross-ref: Poseidon - hashSingle(x)", function()
	for i, vec in TV.Poseidon.hashSingle do
		it(`hashSingle vector {i}: hashSingle({vec[1]})`, function()
			local x = StarkField.fromHex(vec[1])
			local result = Poseidon.hashSingle(x)
			expect(StarkField.toHex(result)):toBe(vec[2])
		end)
	end
end)

describe("Cross-ref: Poseidon - hashMany(values)", function()
	for i, vec in TV.Poseidon.hashMany do
		local values = vec[1] :: { string }
		it(`hashMany vector {i}: {#values} elements`, function()
			local felts = {}
			for _, hex in values do
				table.insert(felts, StarkField.fromHex(hex))
			end
			local result = Poseidon.hashMany(felts)
			expect(StarkField.toHex(result)):toBe(vec[2])
		end)
	end
end)

--------------------------------------------------------------------------------
-- Pedersen cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: Pedersen - hash(a, b)", function()
	for i, vec in TV.Pedersen.hash do
		it(`hash vector {i}: hash({vec[1]}, {vec[2]})`, function()
			local a = StarkField.fromHex(vec[1])
			local b = StarkField.fromHex(vec[2])
			local result = Pedersen.hash(a, b)
			expect(StarkField.toHex(result)):toBe(vec[3])
		end)
	end
end)

--------------------------------------------------------------------------------
-- Keccak / Selector cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: Keccak - keccak256", function()
	for i, vec in TV.Keccak.keccak256 do
		it(`keccak256 vector {i}`, function()
			local inputHex = vec[1]
			local input: buffer
			if inputHex == "" then
				input = buffer.create(0)
			else
				-- Convert hex string to buffer
				local bytes = #inputHex / 2
				input = buffer.create(bytes)
				for j = 0, bytes - 1 do
					local byteHex = string.sub(inputHex, j * 2 + 1, j * 2 + 2)
					buffer.writeu8(input, j, tonumber(byteHex, 16) :: number)
				end
			end
			local hash = Keccak.keccak256(input)
			local hex = Keccak.bufferToHex(hash)
			expect(hex):toBe(vec[2])
		end)
	end
end)

describe("Cross-ref: Keccak - snKeccak", function()
	for i, vec in TV.Keccak.snKeccak do
		it(`snKeccak vector {i}`, function()
			local inputHex = vec[1]
			local input: buffer
			if inputHex == "" then
				input = buffer.create(0)
			else
				local bytes = #inputHex / 2
				input = buffer.create(bytes)
				for j = 0, bytes - 1 do
					local byteHex = string.sub(inputHex, j * 2 + 1, j * 2 + 2)
					buffer.writeu8(input, j, tonumber(byteHex, 16) :: number)
				end
			end
			local result = Keccak.snKeccak(input)
			expect(StarkField.toHex(result)):toBe(vec[2])
		end)
	end
end)

describe("Cross-ref: Keccak - getSelectorFromName", function()
	for i, vec in TV.Keccak.selectors do
		it(`selector vector {i}: getSelectorFromName("{vec[1]}")`, function()
			local selector = Keccak.getSelectorFromName(vec[1])
			expect(StarkField.toHex(selector)):toBe(vec[2])
		end)
	end
end)

--------------------------------------------------------------------------------
-- ECDSA cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: ECDSA - public key derivation", function()
	for i, vec in TV.ECDSA.publicKeys do
		it(`pubkey vector {i}: getPublicKey({vec.privateKey})`, function()
			local privKey = BigInt.fromHex(vec.privateKey)
			local pubKey = StarkCurve.getPublicKey(privKey)
			expect(BigInt.toHex(pubKey.x)):toBe(vec.pubKeyX)
		end)
	end
end)

describe("Cross-ref: ECDSA - sign", function()
	for i, vec in TV.ECDSA.signatures do
		it(`signature vector {i}: sign({vec.messageHash}, ...)`, function()
			local privKey = BigInt.fromHex(vec.privateKey)
			local hash = BigInt.fromHex(vec.messageHash)
			local sig = ECDSA.sign(hash, privKey)
			expect(BigInt.toHex(sig.r)):toBe(vec.r)
			expect(BigInt.toHex(sig.s)):toBe(vec.s)
		end)
	end
end)

describe("Cross-ref: ECDSA - verify", function()
	for i, vec in TV.ECDSA.signatures do
		it(`verify vector {i}: verify({vec.messageHash}, ...)`, function()
			local privKey = BigInt.fromHex(vec.privateKey)
			local hash = BigInt.fromHex(vec.messageHash)
			local pubKey = StarkCurve.getPublicKey(privKey)
			local sig = { r = BigInt.fromHex(vec.r), s = BigInt.fromHex(vec.s) }
			expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- Transaction hash cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: TransactionHash - V3 INVOKE", function()
	for i, vec in TV.TransactionHash.invoke do
		it(`invoke hash vector {i}`, function()
			local hash = TransactionHash.calculateInvokeTransactionHash(vec.params)
			expect(hash):toBe(vec.expected)
		end)
	end
end)

--------------------------------------------------------------------------------
-- Account address cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: Account - address derivation (OZ v0.11)", function()
	for i, vec in TV.Account.addresses do
		it(`address vector {i}: privkey {vec.privateKey}`, function()
			local addr = Account.computeAddress({
				classHash = TV.Account.ozClassHash,
				publicKey = vec.publicKey,
			})
			expect(addr):toBe(vec.addressOZ)
		end)
	end
end)

describe("Cross-ref: Account - address derivation (OZ v0.14)", function()
	for i, vec in TV.Account.addresses do
		it(`address vector {i}: privkey {vec.privateKey}`, function()
			local addr = Account.computeAddress({
				classHash = TV.Account.ozClassHash2,
				publicKey = vec.publicKey,
			})
			expect(addr):toBe(vec.addressOZ2)
		end)
	end
end)

describe("Cross-ref: Account - special cases", function()
	for i, vec in TV.Account.specialCases do
		it(`special case vector {i}`, function()
			local config: any = {
				classHash = vec.classHash,
				publicKey = vec.publicKey,
			}
			if vec.deployer then
				config.deployer = vec.deployer
			end
			if vec.salt then
				config.salt = vec.salt
			end
			local addr = Account.computeAddress(config)
			expect(addr):toBe(vec.expected)
		end)
	end
end)

--------------------------------------------------------------------------------
-- Constants cross-reference
--------------------------------------------------------------------------------

describe("Cross-ref: Constants - chain IDs", function()
	it("SN_MAIN matches", function()
		expect(TransactionHash.SN_MAIN):toBe(TV.Constants.SN_MAIN)
	end)

	it("SN_SEPOLIA matches", function()
		expect(TransactionHash.SN_SEPOLIA):toBe(TV.Constants.SN_SEPOLIA)
	end)
end)

describe("Cross-ref: Constants - curve parameters", function()
	it("Stark prime P round-trips", function()
		local P = BigInt.fromHex(TV.Constants.STARK_PRIME)
		expect(BigInt.toHex(P)):toBe(TV.Constants.STARK_PRIME)
	end)

	it("Curve order N round-trips", function()
		local N = BigInt.fromHex(TV.Constants.CURVE_ORDER)
		expect(BigInt.toHex(N)):toBe(TV.Constants.CURVE_ORDER)
	end)

	it("Generator point G.x matches", function()
		expect(BigInt.toHex(StarkCurve.G.x)):toBe(TV.Constants.GENERATOR_X)
	end)

	it("Generator point G.y matches", function()
		expect(BigInt.toHex(StarkCurve.G.y)):toBe(TV.Constants.GENERATOR_Y)
	end)
end)

describe("Cross-ref: Constants - OZ class hash", function()
	it("Account.OZ_CLASS_HASH matches test vectors", function()
		expect(Account.OZ_CLASS_HASH):toBe(TV.Account.ozClassHash)
	end)
end)

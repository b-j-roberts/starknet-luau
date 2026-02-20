--!strict
local Keccak = require("../../src/crypto/Keccak")
local StarkField = require("../../src/crypto/StarkField")

-- Test vectors from Ethereum/Keccak spec and starknet.js

describe("Keccak - keccak256 raw hash", function()
	it("keccak256('') matches empty string vector", function()
		local input = buffer.create(0)
		local hash = Keccak.keccak256(input)
		local hex = Keccak.bufferToHex(hash)
		expect(hex):toBe("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
	end)

	it("keccak256('abc') matches spec vector", function()
		local input = buffer.create(3)
		buffer.writeu8(input, 0, 0x61) -- 'a'
		buffer.writeu8(input, 1, 0x62) -- 'b'
		buffer.writeu8(input, 2, 0x63) -- 'c'
		local hash = Keccak.keccak256(input)
		local hex = Keccak.bufferToHex(hash)
		expect(hex):toBe("4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
	end)

	it("keccak256 of 448-bit message matches spec", function()
		local msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
		local input = buffer.create(#msg)
		for i = 1, #msg do
			buffer.writeu8(input, i - 1, string.byte(msg, i))
		end
		local hash = Keccak.keccak256(input)
		local hex = Keccak.bufferToHex(hash)
		expect(hex):toBe("45d3b367a6904e6e8d502ee04999a7c27647f91fa845d456525fd352ae3d7371")
	end)

	it("keccak256 of single zero byte", function()
		local input = buffer.create(1)
		buffer.writeu8(input, 0, 0x00)
		local hash = Keccak.keccak256(input)
		local hex = Keccak.bufferToHex(hash)
		expect(hex):toBe("bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a")
	end)

	it("keccak256 output is 32 bytes", function()
		local input = buffer.create(0)
		local hash = Keccak.keccak256(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("keccak256 is NOT SHA-3 (different padding)", function()
		-- SHA-3-256("abc") = 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
		-- Keccak-256("abc") = 4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45
		local input = buffer.create(3)
		buffer.writeu8(input, 0, 0x61)
		buffer.writeu8(input, 1, 0x62)
		buffer.writeu8(input, 2, 0x63)
		local hash = Keccak.keccak256(input)
		local hex = Keccak.bufferToHex(hash)
		-- Verify we are NOT producing SHA-3 output
		expect(hex):toBe("4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
		local isSha3 = hex == "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
		expect(isSha3):toBe(false)
	end)
end)

describe("Keccak - snKeccak (250-bit masked)", function()
	it("snKeccak returns a valid StarkField Felt", function()
		local input = buffer.create(3)
		buffer.writeu8(input, 0, 0x61) -- 'a'
		buffer.writeu8(input, 1, 0x62) -- 'b'
		buffer.writeu8(input, 2, 0x63) -- 'c'
		local result = Keccak.snKeccak(input)
		-- Result should be non-zero
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("snKeccak output fits in 250 bits (top 6 bits are zero)", function()
		-- Hash "transfer" and verify the result is < 2^250
		local msg = "transfer"
		local input = buffer.create(#msg)
		for i = 1, #msg do
			buffer.writeu8(input, i - 1, string.byte(msg, i))
		end
		local result = Keccak.snKeccak(input)
		local hex = StarkField.toHex(result)
		-- The hex representation (without 0x prefix) should be at most 63 hex chars
		-- (250 bits = 62.5 hex chars, so at most 63 with leading digit <= 3)
		local hexBody = string.sub(hex, 3) -- strip "0x"
		expect(#hexBody <= 63):toBe(true)
	end)

	it("snKeccak of empty input matches masked keccak256", function()
		local input = buffer.create(0)
		local result = Keccak.snKeccak(input)
		-- keccak256("") = c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
		-- Masked to 250 bits: clear top 6 bits of byte 0 (0xc5 -> 0x01)
		-- = 01d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
		local expected = StarkField.fromHex("0x01d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
		expect(StarkField.eq(result, expected)):toBe(true)
	end)
end)

describe("Keccak - getSelectorFromName", function()
	it("getSelectorFromName('transfer') matches starknet.js", function()
		local selector = Keccak.getSelectorFromName("transfer")
		expect(StarkField.toHex(selector)):toBe("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e")
	end)

	it("getSelectorFromName('balanceOf') matches starknet.js", function()
		local selector = Keccak.getSelectorFromName("balanceOf")
		expect(StarkField.toHex(selector)):toBe("0x2e4263afad30923c891518314c3c95dbe830a16874e8abc5777a9a20b54c76e")
	end)

	it("getSelectorFromName('balance_of') matches starknet.js", function()
		local selector = Keccak.getSelectorFromName("balance_of")
		expect(StarkField.toHex(selector)):toBe("0x35a73cd311a05d46deda634c5ee045db92f811b4e74bca4437fcb5302b7af33")
	end)

	it("getSelectorFromName('approve') matches starknet.js", function()
		local selector = Keccak.getSelectorFromName("approve")
		expect(StarkField.toHex(selector)):toBe("0x219209e083275171774dab1df80982e9df2096516f06319c5c6d71ae0a8480c")
	end)

	it("getSelectorFromName('__default__') returns zero", function()
		local selector = Keccak.getSelectorFromName("__default__")
		expect(StarkField.isZero(selector)):toBe(true)
	end)

	it("getSelectorFromName('__l1_default__') returns zero", function()
		local selector = Keccak.getSelectorFromName("__l1_default__")
		expect(StarkField.isZero(selector)):toBe(true)
	end)

	it("different function names produce different selectors", function()
		local s1 = Keccak.getSelectorFromName("transfer")
		local s2 = Keccak.getSelectorFromName("approve")
		expect(StarkField.eq(s1, s2)):toBe(false)
	end)

	it("getSelectorFromName is deterministic", function()
		local s1 = Keccak.getSelectorFromName("transfer")
		local s2 = Keccak.getSelectorFromName("transfer")
		expect(StarkField.eq(s1, s2)):toBe(true)
	end)
end)

describe("Keccak - edge cases", function()
	it("keccak256 of exactly 136 bytes (one full rate block)", function()
		-- Input that exactly fills one rate block (136 bytes) triggers a second padding block
		local input = buffer.create(136)
		for i = 0, 135 do
			buffer.writeu8(input, i, i % 256)
		end
		local hash = Keccak.keccak256(input)
		-- Just verify it produces a 32-byte output without error
		expect(buffer.len(hash)):toBe(32)
	end)

	it("keccak256 of 135 bytes (rate - 1, minimal padding)", function()
		local input = buffer.create(135)
		for i = 0, 134 do
			buffer.writeu8(input, i, i % 256)
		end
		local hash = Keccak.keccak256(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("keccak256 of 137 bytes (rate + 1)", function()
		local input = buffer.create(137)
		for i = 0, 136 do
			buffer.writeu8(input, i, i % 256)
		end
		local hash = Keccak.keccak256(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("keccak256 of single byte 0xFF", function()
		local input = buffer.create(1)
		buffer.writeu8(input, 0, 0xFF)
		local hash = Keccak.keccak256(input)
		-- Just verify it completes and returns valid output
		expect(buffer.len(hash)):toBe(32)
		-- keccak256(0xFF) should not be all zeros
		local allZero = true
		for i = 0, 31 do
			if buffer.readu8(hash, i) ~= 0 then
				allZero = false
				break
			end
		end
		expect(allZero):toBe(false)
	end)
end)

describe("Keccak - bufferToHex utility", function()
	it("converts empty buffer to empty string", function()
		local buf = buffer.create(0)
		expect(Keccak.bufferToHex(buf)):toBe("")
	end)

	it("converts single byte correctly", function()
		local buf = buffer.create(1)
		buffer.writeu8(buf, 0, 0xAB)
		expect(Keccak.bufferToHex(buf)):toBe("ab")
	end)

	it("converts multi-byte buffer correctly", function()
		local buf = buffer.create(4)
		buffer.writeu8(buf, 0, 0xDE)
		buffer.writeu8(buf, 1, 0xAD)
		buffer.writeu8(buf, 2, 0xBE)
		buffer.writeu8(buf, 3, 0xEF)
		expect(Keccak.bufferToHex(buf)):toBe("deadbeef")
	end)
end)

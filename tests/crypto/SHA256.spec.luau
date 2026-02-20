--!strict
local SHA256 = require("../../src/crypto/SHA256")

-- Helper: create a buffer from an ASCII string
local function stringToBuffer(s: string): buffer
	local buf = buffer.create(#s)
	for i = 1, #s do
		buffer.writeu8(buf, i - 1, string.byte(s, i))
	end
	return buf
end

-- Helper: create a buffer from a hex string (no prefix)
local function hexToBuffer(hex: string): buffer
	local len = #hex / 2
	local buf = buffer.create(len)
	for i = 0, len - 1 do
		local byte = tonumber(string.sub(hex, i * 2 + 1, i * 2 + 2), 16) :: number
		buffer.writeu8(buf, i, byte)
	end
	return buf
end

-- Helper: create a buffer filled with a repeated byte value
local function filledBuffer(length: number, value: number): buffer
	local buf = buffer.create(length)
	for i = 0, length - 1 do
		buffer.writeu8(buf, i, value)
	end
	return buf
end

-- NIST test vectors: https://csrc.nist.gov/projects/cryptographic-standards-and-guidelines

describe("SHA256 - hash (NIST test vectors)", function()
	it("SHA-256('') matches NIST empty string vector", function()
		local input = buffer.create(0)
		local hash = SHA256.hash(input)
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	end)

	it("SHA-256('abc') matches NIST one-block vector", function()
		local hash = SHA256.hash(stringToBuffer("abc"))
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	end)

	it("SHA-256 of 448-bit message matches NIST two-block vector", function()
		local msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
		local hash = SHA256.hash(stringToBuffer(msg))
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
	end)

	it("SHA-256 of 896-bit message matches NIST vector", function()
		local msg =
			"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
		local hash = SHA256.hash(stringToBuffer(msg))
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
	end)

	it("SHA-256('a') matches known vector", function()
		local hash = SHA256.hash(stringToBuffer("a"))
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
	end)

	it("SHA-256 output is always 32 bytes", function()
		local hash = SHA256.hash(buffer.create(0))
		expect(buffer.len(hash)):toBe(32)
	end)
end)

describe("SHA256 - hash (padding edge cases)", function()
	it("55-byte input (exactly fills padding to one block)", function()
		-- 55 + 1 (0x80) + 8 (length) = 64 bytes = one block
		local input = filledBuffer(55, 0x61)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
		-- Verify determinism
		local hash2 = SHA256.hash(input)
		expect(SHA256.bufferToHex(hash)):toBe(SHA256.bufferToHex(hash2))
	end)

	it("56-byte input (triggers second block for padding)", function()
		-- 56 + 1 (0x80) + 8 (length) = 65 > 64, needs 2 blocks
		local input = filledBuffer(56, 0x61)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("64-byte input (exactly one block of data)", function()
		local input = filledBuffer(64, 0x61)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("63-byte input (block size - 1)", function()
		local input = filledBuffer(63, 0x61)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("128-byte input (two full blocks of data)", function()
		local input = filledBuffer(128, 0x42)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
	end)

	it("single zero byte", function()
		local input = buffer.create(1)
		buffer.writeu8(input, 0, 0x00)
		local hash = SHA256.hash(input)
		local hex = SHA256.bufferToHex(hash)
		expect(hex):toBe("6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d")
	end)

	it("single 0xFF byte", function()
		local input = buffer.create(1)
		buffer.writeu8(input, 0, 0xFF)
		local hash = SHA256.hash(input)
		expect(buffer.len(hash)):toBe(32)
		-- Should not be all zeros
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

describe("SHA256 - hash (determinism and distinctness)", function()
	it("same input produces same hash", function()
		local input = stringToBuffer("hello world")
		local h1 = SHA256.hash(input)
		local h2 = SHA256.hash(input)
		expect(SHA256.bufferToHex(h1)):toBe(SHA256.bufferToHex(h2))
	end)

	it("different inputs produce different hashes", function()
		local h1 = SHA256.hash(stringToBuffer("hello"))
		local h2 = SHA256.hash(stringToBuffer("world"))
		local hex1 = SHA256.bufferToHex(h1)
		local hex2 = SHA256.bufferToHex(h2)
		expect(hex1 == hex2):toBe(false)
	end)

	it("SHA-256 is NOT the same as Keccak-256", function()
		local input = stringToBuffer("abc")
		local hash = SHA256.hash(input)
		local hex = SHA256.bufferToHex(hash)
		-- Keccak-256("abc") = 4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45
		local isKeccak = hex == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
		expect(isKeccak):toBe(false)
		-- SHA-256("abc") should be the correct NIST value
		expect(hex):toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	end)
end)

-- HMAC-SHA-256 test vectors from RFC 4231

describe("SHA256 - hmac (RFC 4231 test vectors)", function()
	it("Test Case 1: short key, 'Hi There'", function()
		local key = filledBuffer(20, 0x0b)
		local data = stringToBuffer("Hi There")
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
	end)

	it("Test Case 2: key='Jefe', 'what do ya want for nothing?'", function()
		local key = stringToBuffer("Jefe")
		local data = stringToBuffer("what do ya want for nothing?")
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	end)

	it("Test Case 3: 20-byte 0xaa key, 50-byte 0xdd data", function()
		local key = filledBuffer(20, 0xaa)
		local data = filledBuffer(50, 0xdd)
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe")
	end)

	it("Test Case 4: incrementing key, 50-byte 0xcd data", function()
		local key = hexToBuffer("0102030405060708090a0b0c0d0e0f10111213141516171819")
		local data = filledBuffer(50, 0xcd)
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b")
	end)

	it("Test Case 6: 131-byte key (longer than block size), hash key first", function()
		local key = filledBuffer(131, 0xaa)
		local data = stringToBuffer("Test Using Larger Than Block-Size Key - Hash Key First")
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
	end)

	it("Test Case 7: 131-byte key, longer data", function()
		local key = filledBuffer(131, 0xaa)
		local data = stringToBuffer(
			"This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."
		)
		local mac = SHA256.hmac(key, data)
		local hex = SHA256.bufferToHex(mac)
		expect(hex):toBe("9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2")
	end)
end)

describe("SHA256 - hmac (edge cases)", function()
	it("HMAC with empty message", function()
		local key = filledBuffer(32, 0x0b)
		local data = buffer.create(0)
		local mac = SHA256.hmac(key, data)
		expect(buffer.len(mac)):toBe(32)
	end)

	it("HMAC with exactly 64-byte key (block size)", function()
		local key = filledBuffer(64, 0xaa)
		local data = stringToBuffer("test")
		local mac = SHA256.hmac(key, data)
		expect(buffer.len(mac)):toBe(32)
	end)

	it("HMAC with 65-byte key (block size + 1, triggers hashing)", function()
		local key = filledBuffer(65, 0xaa)
		local data = stringToBuffer("test")
		local mac = SHA256.hmac(key, data)
		expect(buffer.len(mac)):toBe(32)
	end)

	it("HMAC is deterministic", function()
		local key = stringToBuffer("secret")
		local data = stringToBuffer("message")
		local mac1 = SHA256.hmac(key, data)
		local mac2 = SHA256.hmac(key, data)
		expect(SHA256.bufferToHex(mac1)):toBe(SHA256.bufferToHex(mac2))
	end)

	it("different keys produce different MACs", function()
		local data = stringToBuffer("message")
		local mac1 = SHA256.hmac(stringToBuffer("key1"), data)
		local mac2 = SHA256.hmac(stringToBuffer("key2"), data)
		expect(SHA256.bufferToHex(mac1) == SHA256.bufferToHex(mac2)):toBe(false)
	end)

	it("different messages produce different MACs", function()
		local key = stringToBuffer("key")
		local mac1 = SHA256.hmac(key, stringToBuffer("msg1"))
		local mac2 = SHA256.hmac(key, stringToBuffer("msg2"))
		expect(SHA256.bufferToHex(mac1) == SHA256.bufferToHex(mac2)):toBe(false)
	end)
end)

describe("SHA256 - bufferToHex utility", function()
	it("converts empty buffer to empty string", function()
		local buf = buffer.create(0)
		expect(SHA256.bufferToHex(buf)):toBe("")
	end)

	it("converts single byte correctly", function()
		local buf = buffer.create(1)
		buffer.writeu8(buf, 0, 0xAB)
		expect(SHA256.bufferToHex(buf)):toBe("ab")
	end)

	it("converts multi-byte buffer correctly", function()
		local buf = buffer.create(4)
		buffer.writeu8(buf, 0, 0xDE)
		buffer.writeu8(buf, 1, 0xAD)
		buffer.writeu8(buf, 2, 0xBE)
		buffer.writeu8(buf, 3, 0xEF)
		expect(SHA256.bufferToHex(buf)):toBe("deadbeef")
	end)
end)

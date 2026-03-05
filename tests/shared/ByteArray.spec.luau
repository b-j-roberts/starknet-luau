--!strict
local ByteArray = require("../../src/shared/ByteArray")

describe("ByteArray", function()
	describe("hexToString", function()
		it("converts simple hex to string", function()
			expect(ByteArray.hexToString("0x68656c6c6f", 5)):toBe("hello")
		end)

		it("left-pads short hex values", function()
			-- "0x41" = 'A', with numBytes=1
			expect(ByteArray.hexToString("0x41", 1)):toBe("A")
		end)

		it("handles zero value", function()
			expect(ByteArray.hexToString("0x0", 1)):toBe("\0")
		end)

		it("pads to full 31-byte chunk", function()
			local result = ByteArray.hexToString("0x41", 31)
			expect(#result):toBe(31)
			-- 30 null bytes followed by 'A'
			expect(string.byte(result, 31)):toBe(0x41)
		end)
	end)

	describe("encode", function()
		it("encodes empty string", function()
			local r = ByteArray.encode("")
			expect(#r):toBe(3) -- [numChunks, pendingWord, pendingLen]
			expect(r[1]):toBe("0x0") -- 0 full chunks
			expect(r[2]):toBe("0x0") -- no pending
			expect(r[3]):toBe("0x0") -- 0 pending len
		end)

		it("encodes short string (< 31 chars)", function()
			local r = ByteArray.encode("hello")
			expect(#r):toBe(3) -- [0 chunks, pending, pendingLen]
			expect(r[1]):toBe("0x0") -- 0 full chunks
			expect(r[2]):toBe("0x68656c6c6f") -- "hello" as hex
			expect(r[3]):toBe("0x5") -- 5 bytes pending
		end)

		it("encodes exactly 31-byte string (one full chunk)", function()
			local str = string.rep("a", 31)
			local r = ByteArray.encode(str)
			expect(#r):toBe(4) -- [1 chunk, chunk0, pending=0x0, pendingLen=0]
			expect(r[1]):toBe("0x1") -- 1 full chunk
			-- chunk0 = 31 'a' bytes = 0x6161...61
			expect(r[3]):toBe("0x0") -- no pending
			expect(r[4]):toBe("0x0") -- 0 pending len
		end)

		it("encodes 32-byte string (1 full chunk + 1 pending)", function()
			local str = string.rep("a", 31) .. "b"
			local r = ByteArray.encode(str)
			expect(#r):toBe(4) -- [1 chunk, chunk0, pending, pendingLen]
			expect(r[1]):toBe("0x1") -- 1 full chunk
			expect(r[3]):toBe("0x62") -- 'b' as hex
			expect(r[4]):toBe("0x1") -- 1 byte pending
		end)

		it("encodes 62-byte string (2 full chunks)", function()
			local str = string.rep("x", 62)
			local r = ByteArray.encode(str)
			expect(#r):toBe(5) -- [2 chunks, chunk0, chunk1, pending=0x0, pendingLen=0]
			expect(r[1]):toBe("0x2") -- 2 full chunks
			expect(r[4]):toBe("0x0") -- no pending
			expect(r[5]):toBe("0x0") -- 0 pending len
		end)
	end)

	describe("decode", function()
		it("decode roundtrips with encode for empty string", function()
			local encoded = ByteArray.encode("")
			local decoded, consumed = ByteArray.decode(encoded, 1)
			expect(decoded):toBe("")
			expect(consumed):toBe(3)
		end)

		it("decode roundtrips with encode for short string", function()
			local encoded = ByteArray.encode("hello world")
			local decoded, consumed = ByteArray.decode(encoded, 1)
			expect(decoded):toBe("hello world")
			expect(consumed):toBe(3)
		end)

		it("decode roundtrips with encode for exactly 31 bytes", function()
			local str = string.rep("A", 31)
			local encoded = ByteArray.encode(str)
			local decoded, consumed = ByteArray.decode(encoded, 1)
			expect(decoded):toBe(str)
			expect(consumed):toBe(4)
		end)

		it("decode roundtrips with encode for multi-chunk string", function()
			local str = string.rep("B", 65) -- 2 full chunks + 3 pending
			local encoded = ByteArray.encode(str)
			local decoded, consumed = ByteArray.decode(encoded, 1)
			expect(decoded):toBe(str)
			expect(consumed):toBe(5) -- numChunks + 2 chunks + pending + pendingLen
		end)

		it("decodes from non-zero offset", function()
			-- Simulate felt array with prefix data
			local encoded = ByteArray.encode("test")
			local withPrefix = { "0xdead", "0xbeef" }
			for _, v in encoded do
				table.insert(withPrefix, v)
			end
			local decoded, consumed = ByteArray.decode(withPrefix, 3) -- offset past prefix
			expect(decoded):toBe("test")
			expect(consumed):toBe(3)
		end)

		it("handles zero-length pending word correctly", function()
			-- Exactly 62 bytes = 2 full chunks, no pending
			local str = string.rep("C", 62)
			local encoded = ByteArray.encode(str)
			local decoded, _ = ByteArray.decode(encoded, 1)
			expect(decoded):toBe(str)
		end)
	end)
end)

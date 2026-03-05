--!strict
local HexUtils = require("../../src/shared/HexUtils")

describe("HexUtils", function()
	describe("hasHexPrefix", function()
		it("returns true for 0x prefix", function()
			expect(HexUtils.hasHexPrefix("0x1234")):toBe(true)
		end)

		it("returns true for 0X prefix", function()
			expect(HexUtils.hasHexPrefix("0X1234")):toBe(true)
		end)

		it("returns false for no prefix", function()
			expect(HexUtils.hasHexPrefix("1234")):toBe(false)
		end)

		it("returns false for empty string", function()
			expect(HexUtils.hasHexPrefix("")):toBe(false)
		end)

		it("returns false for short strings", function()
			expect(HexUtils.hasHexPrefix("0")):toBe(false)
		end)
	end)

	describe("normalizeHex", function()
		it("normalizes with 0x prefix", function()
			expect(HexUtils.normalizeHex("0x01")):toBe("0x1")
		end)

		it("strips leading zeros", function()
			expect(HexUtils.normalizeHex("0x000abc")):toBe("0xabc")
		end)

		it("handles zero", function()
			expect(HexUtils.normalizeHex("0x0")):toBe("0x0")
		end)

		it("lowercases hex", function()
			expect(HexUtils.normalizeHex("0xABCDEF")):toBe("0xabcdef")
		end)

		it("handles full Stark felt", function()
			local result = HexUtils.normalizeHex("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
			expect(result):toBe("0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
		end)

		it("normalizes uppercase address with leading zeros", function()
			expect(HexUtils.normalizeHex("0x00ABC")):toBe("0xabc")
		end)
	end)

	describe("asciiToHex", function()
		it("returns 0x0 for empty string", function()
			expect(HexUtils.asciiToHex("")):toBe("0x0")
		end)

		it("encodes single character", function()
			expect(HexUtils.asciiToHex("a")):toBe("0x61")
		end)

		it("encodes 'abc'", function()
			expect(HexUtils.asciiToHex("abc")):toBe("0x616263")
		end)

		it("encodes 'transfer'", function()
			expect(HexUtils.asciiToHex("transfer")):toBe("0x7472616e73666572")
		end)

		it("encodes 'StarkNet Message'", function()
			expect(HexUtils.asciiToHex("StarkNet Message")):toBe("0x537461726b4e6574204d657373616765")
		end)

		it("encodes max 31-char string", function()
			local str31 = string.rep("a", 31)
			local result = HexUtils.asciiToHex(str31)
			expect(#result):toBe(2 + 62) -- "0x" + 31*2 hex chars
		end)
	end)

	describe("parseHexToNumber", function()
		it("parses 0x prefix", function()
			expect(HexUtils.parseHexToNumber("0x1a")):toBe(26)
		end)

		it("parses without prefix", function()
			expect(HexUtils.parseHexToNumber("1a")):toBe(26)
		end)

		it("parses 0x0", function()
			expect(HexUtils.parseHexToNumber("0x0")):toBe(0)
		end)

		it("parses 0xff", function()
			expect(HexUtils.parseHexToNumber("0xff")):toBe(255)
		end)

		it("returns 0 for empty string", function()
			expect(HexUtils.parseHexToNumber("")):toBe(0)
		end)

		it("parses large number", function()
			expect(HexUtils.parseHexToNumber("0x100")):toBe(256)
		end)

		it("parses decimal-looking hex", function()
			expect(HexUtils.parseHexToNumber("0x10")):toBe(16)
		end)

		it("handles uppercase", function()
			expect(HexUtils.parseHexToNumber("0xFF")):toBe(255)
		end)
	end)
end)

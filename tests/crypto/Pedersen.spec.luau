--!strict
local StarkField = require("../../src/crypto/StarkField")
local StarkCurve = require("../../src/crypto/StarkCurve")
local Pedersen = require("../../src/crypto/Pedersen")

-- Test vectors from starknet-crypto-py (cross-referenced with starknet.js computePedersenHash)

describe("Pedersen - hash(a, b)", function()
	it("hash(0, 0) returns shift point x-coordinate", function()
		local a = StarkField.zero()
		local b = StarkField.zero()
		local result = Pedersen.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x49ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804")
	end)

	it("hash(1, 2) matches starknet.js", function()
		local a = StarkField.fromNumber(1)
		local b = StarkField.fromNumber(2)
		local result = Pedersen.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x5bb9440e27889a364bcb678b1f679ecd1347acdedcbf36e83494f857cc58026")
	end)

	it("hash(0x12773, 0x872362) matches starknet.js", function()
		local a = StarkField.fromHex("0x12773")
		local b = StarkField.fromHex("0x872362")
		local result = Pedersen.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x5ed2703dfdb505c587700ce2ebfcab5b3515cd7e6114817e6026ec9d4b364ca")
	end)

	it("hash with large field elements matches starknet.js", function()
		local a = StarkField.fromHex("0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb")
		local b = StarkField.fromHex("0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a")
		local result = Pedersen.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x30e480bed5fe53fa909cc0f8c4d99b8f9f2c016be4c41e13a4848797979c662")
	end)

	it("hash with another large pair matches starknet.js", function()
		local a = StarkField.fromHex("0x58f580910a6ca59b28927c08fe6c43e2e303ca384571a7093e18e6f424dee7")
		local b = StarkField.fromHex("0x78734f65a067be9bdb39de18434d71e79f7b6466a4b66bdf13f0c0c6c743200")
		local result = Pedersen.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x447cd054d05f8eb79219632f837e488c19166c648a0d60cc094aed79258169d")
	end)
end)

describe("Pedersen - commutativity and determinism", function()
	it("hash is not commutative (hash(1,2) != hash(2,1))", function()
		local h12 = Pedersen.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		local h21 = Pedersen.hash(StarkField.fromNumber(2), StarkField.fromNumber(1))
		expect(StarkField.eq(h12, h21)):toBe(false)
	end)

	it("hash output is deterministic", function()
		local a = StarkField.fromNumber(42)
		local b = StarkField.fromNumber(99)
		local r1 = Pedersen.hash(a, b)
		local r2 = Pedersen.hash(a, b)
		expect(StarkField.eq(r1, r2)):toBe(true)
	end)
end)

describe("Pedersen - constant points validation", function()
	it("shift point is on the Stark curve", function()
		local shift = {
			x = StarkField.fromHex("0x049ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804"),
			y = StarkField.fromHex("0x03ca0cfe4b3bc6ddf346d49d06ea0ed34e621062c0e056c1d0405d266e10268a"),
		}
		expect(StarkCurve.isOnCurve(shift)):toBe(true)
	end)

	it("P0 is on the Stark curve", function()
		local p0 = {
			x = StarkField.fromHex("0x0234287dcbaffe7f969c748655fca9e58fa8120b6d56eb0c1080d17957ebe47b"),
			y = StarkField.fromHex("0x03b056f100f96fb21e889527d41f4e39940135dd7a6c94cc6ed0268ee89e5615"),
		}
		expect(StarkCurve.isOnCurve(p0)):toBe(true)
	end)

	it("P1 is on the Stark curve", function()
		local p1 = {
			x = StarkField.fromHex("0x04fa56f376c83db33f9dab2656558f3399099ec1de5e3018b7a6932dba8aa378"),
			y = StarkField.fromHex("0x03fa0984c931c9e38113e0c0e47e4401562761f92a7a23b45168f4e80ff5b54d"),
		}
		expect(StarkCurve.isOnCurve(p1)):toBe(true)
	end)

	it("P2 is on the Stark curve", function()
		local p2 = {
			x = StarkField.fromHex("0x04ba4cc166be8dec764910f75b45f74b40c690c74709e90f3aa372f0bd2d6997"),
			y = StarkField.fromHex("0x0040301cf5c1751f4b971e46c4ede85fcac5c59a5ce5ae7c48151f27b24b219c"),
		}
		expect(StarkCurve.isOnCurve(p2)):toBe(true)
	end)

	it("P3 is on the Stark curve", function()
		local p3 = {
			x = StarkField.fromHex("0x054302dcb0e6cc1c6e44cca8f61a63bb2ca65048d53fb325d36ff12c49a58202"),
			y = StarkField.fromHex("0x01b77b3e37d13504b348046268d8ae25ce98ad783c25561a879dcc77e99c2426"),
		}
		expect(StarkCurve.isOnCurve(p3)):toBe(true)
	end)
end)

describe("Pedersen - properties", function()
	it("hash output is non-zero for zero inputs", function()
		local result = Pedersen.hash(StarkField.zero(), StarkField.zero())
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("different inputs produce different hashes", function()
		local h1 = Pedersen.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		local h2 = Pedersen.hash(StarkField.fromNumber(3), StarkField.fromNumber(4))
		expect(StarkField.eq(h1, h2)):toBe(false)
	end)

	it("hash output is a valid field element (round-trips through hex)", function()
		local result = Pedersen.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		local hex = StarkField.toHex(result)
		expect(string.sub(hex, 1, 2)):toBe("0x")
		local reparsed = StarkField.fromHex(hex)
		expect(StarkField.eq(result, reparsed)):toBe(true)
	end)

	it("hash(a, 0) differs from hash(0, a) for non-zero a", function()
		local a = StarkField.fromNumber(12345)
		local h1 = Pedersen.hash(a, StarkField.zero())
		local h2 = Pedersen.hash(StarkField.zero(), a)
		expect(StarkField.eq(h1, h2)):toBe(false)
	end)

	it("hash with max 4-bit high nibble (bits 248-251 set)", function()
		-- Value with bits 248-251 all set = 0xF << 248
		local val = StarkField.fromHex("0xf00000000000000000000000000000000000000000000000000000000000000")
		local result = Pedersen.hash(val, StarkField.zero())
		-- Just verify it completes without error and returns non-zero
		expect(StarkField.isZero(result)):toBe(false)
	end)
end)

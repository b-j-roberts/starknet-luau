--!strict
-- Comprehensive test vectors cross-referenced from starknet.js / @scure/starknet
-- These are the canonical known-good values for validating all crypto primitives.
-- Source references:
--   starknet.js: https://github.com/starknet-io/starknet.js
--   @scure/starknet: https://github.com/paulmillr/scure-starknet
--   Ethereum Keccak spec: https://keccak.team/
--   SNIP-8: Starknet transaction hash specification

local TestVectors = {}

--------------------------------------------------------------------------------
-- BigInt arithmetic vectors
-- Cross-referenced from manual computation and starknet field properties
--------------------------------------------------------------------------------

TestVectors.BigInt = {
	-- Format: { a, b, expected_result }
	add = {
		{ "0x1", "0x2", "0x3" },
		{ "0x0", "0x0", "0x0" },
		{ "0xff", "0x1", "0x100" },
		{ "0xffffffff", "0x1", "0x100000000" },
		{ "0xdeadbeef", "0xcafebabe", "0x1a9ac79ad" },
		-- Large: Stark prime - 1 + 1 = Stark prime
		{
			"0x800000000000011000000000000000000000000000000000000000000000000",
			"0x1",
			"0x800000000000011000000000000000000000000000000000000000000000001",
		},
	},
	sub = {
		{ "0x3", "0x2", "0x1" },
		{ "0x100", "0x1", "0xff" },
		{ "0x100000000", "0x1", "0xffffffff" },
	},
	mul = {
		{ "0x2", "0x3", "0x6" },
		{ "0xff", "0xff", "0xfe01" },
		{ "0x0", "0xdeadbeef", "0x0" },
		{ "0x1", "0xdeadbeef", "0xdeadbeef" },
		{ "0x10000", "0x10000", "0x100000000" },
	},
	-- Modular arithmetic with Stark prime P
	-- P = 0x800000000000011000000000000000000000000000000000000000000000001
	modular = {
		-- a mod P = a when a < P
		{
			op = "mod",
			a = "0x1",
			m = "0x800000000000011000000000000000000000000000000000000000000000001",
			expected = "0x1",
		},
		-- P mod P = 0
		{
			op = "mod",
			a = "0x800000000000011000000000000000000000000000000000000000000000001",
			m = "0x800000000000011000000000000000000000000000000000000000000000001",
			expected = "0x0",
		},
		-- (P + 1) mod P = 1
		{
			op = "addmod",
			a = "0x800000000000011000000000000000000000000000000000000000000000001",
			b = "0x1",
			m = "0x800000000000011000000000000000000000000000000000000000000000001",
			expected = "0x1",
		},
		-- 2 * invmod(2, P) mod P = 1
		{
			op = "invmod",
			a = "0x2",
			m = "0x800000000000011000000000000000000000000000000000000000000000001",
			expected = "0x400000000000008800000000000000000000000000000000000000000000001",
		},
	},
	-- Hex round-trip vectors
	hexRoundTrip = {
		"0x0",
		"0x1",
		"0x2a",
		"0xff",
		"0xdeadbeef",
		"0xcafebabe",
		"0x800000000000011000000000000000000000000000000000000000000000001",
		"0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f",
	},
	-- Comparison vectors: { a, b, expected_cmp } where cmp is -1, 0, or 1
	comparison = {
		{ "0x0", "0x0", 0 },
		{ "0x1", "0x0", 1 },
		{ "0x0", "0x1", -1 },
		{ "0xff", "0xff", 0 },
		{ "0x100", "0xff", 1 },
		{ "0xdeadbeef", "0xcafebabe", 1 },
	},
	-- Bit operations
	bitOps = {
		-- { a, bits, expected_shl }
		shl = {
			{ "0x1", 1, "0x2" },
			{ "0x1", 8, "0x100" },
			{ "0x1", 32, "0x100000000" },
			{ "0xff", 4, "0xff0" },
		},
		-- { a, bits, expected_shr }
		shr = {
			{ "0x100", 1, "0x80" },
			{ "0x100", 8, "0x1" },
			{ "0xff0", 4, "0xff" },
		},
		-- { a, b, expected_band }
		band = {
			{ "0xff", "0x0f", "0xf" },
			{ "0xdeadbeef", "0xff00ff00", "0xde00be00" },
		},
	},
}

--------------------------------------------------------------------------------
-- Poseidon hash vectors
-- Cross-referenced from starknet.js poseidonHash / @scure/starknet
--------------------------------------------------------------------------------

TestVectors.Poseidon = {
	-- hash(a, b) vectors: { a, b, expected }
	hash = {
		{ "0x1", "0x2", "0x5d44a3decb2b2e0cc71071f7b802f45dd792d064f0fc7316c46514f70f9891a" },
		{ "0x0", "0x0", "0x293d3e8a80f400daaaffdd5932e2bcc8814bab8f414a75dcacf87318f8b14c5" },
		{ "0x1", "0x0", "0x7752582c54a42fe0fa35c40f07293bb7d8efe90e21d8d2c06a7db52d7d9b7a1" },
		{ "0x0", "0x1", "0x5134197931125e849424475aa20cd6ca0ce8603b79177c3f76e2119c8f98c53" },
		{
			"0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb",
			"0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a",
			"0x67c6a2e2d0c7867f97444ae17956dbc89d40ad22255bb06f5f6c515958926ed",
		},
	},
	-- hashSingle(x) vectors: { x, expected }
	hashSingle = {
		{ "0x1", "0x6d226d4c804cd74567f5ac59c6a4af1fe2a6eced19fb7560a9124579877da25" },
		{ "0x0", "0x60009f680a43e6f760790f76214b26243464cdd4f31fdc460baf66d32897c1b" },
	},
	-- hashMany(values) vectors: { values, expected }
	hashMany = {
		{ {}, "0x2272be0f580fd156823304800919530eaa97430e972d7213ee13f4fbf7a5dbc" },
		{ { "0x1" }, "0x579e8877c7755365d5ec1ec7d3a94a457eff5d1f40482bbe9729c064cdead2" },
		{ { "0x1", "0x2" }, "0x371cb6995ea5e7effcd2e174de264b5b407027a75a231a70c2c8d196107f0e7" },
		{ { "0x1", "0x2", "0x3" }, "0x2f0d8840bcf3bc629598d8a6cc80cb7c0d9e52d93dab244bbf9cd0dca0ad082" },
		{ { "0x1", "0x2", "0x3", "0x4" }, "0x26e3ad8b876e02bc8a4fc43dad40a8f81a6384083cabffa190bcf40d512ae1d" },
	},
}

--------------------------------------------------------------------------------
-- Pedersen hash vectors
-- Cross-referenced from starknet.js computePedersenHash / starknet-crypto-py
--------------------------------------------------------------------------------

TestVectors.Pedersen = {
	-- hash(a, b) vectors: { a, b, expected }
	hash = {
		{ "0x0", "0x0", "0x49ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804" },
		{ "0x1", "0x2", "0x5bb9440e27889a364bcb678b1f679ecd1347acdedcbf36e83494f857cc58026" },
		{ "0x12773", "0x872362", "0x5ed2703dfdb505c587700ce2ebfcab5b3515cd7e6114817e6026ec9d4b364ca" },
		{
			"0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb",
			"0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a",
			"0x30e480bed5fe53fa909cc0f8c4d99b8f9f2c016be4c41e13a4848797979c662",
		},
		{
			"0x58f580910a6ca59b28927c08fe6c43e2e303ca384571a7093e18e6f424dee7",
			"0x78734f65a067be9bdb39de18434d71e79f7b6466a4b66bdf13f0c0c6c743200",
			"0x447cd054d05f8eb79219632f837e488c19166c648a0d60cc094aed79258169d",
		},
	},
}

--------------------------------------------------------------------------------
-- Keccak / Selector vectors
-- Cross-referenced from Ethereum Keccak spec, starknet.js getSelectorFromName
--------------------------------------------------------------------------------

TestVectors.Keccak = {
	-- keccak256 raw hash vectors: { inputHex (or empty string for empty), expected }
	keccak256 = {
		{ "", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470" },
		{ "616263", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45" }, -- "abc"
		{ "00", "bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a" }, -- single zero byte
	},
	-- snKeccak vectors (250-bit masked): { inputHex, expected }
	snKeccak = {
		{ "", "0x1d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470" },
	},
	-- getSelectorFromName vectors: { functionName, expected }
	selectors = {
		{ "transfer", "0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e" },
		{ "balanceOf", "0x2e4263afad30923c891518314c3c95dbe830a16874e8abc5777a9a20b54c76e" },
		{ "balance_of", "0x35a73cd311a05d46deda634c5ee045db92f811b4e74bca4437fcb5302b7af33" },
		{ "approve", "0x219209e083275171774dab1df80982e9df2096516f06319c5c6d71ae0a8480c" },
		{ "transferFrom", "0x41b033f4a31df8067c24d1e9b550a2ce75fd4a29e1147af9752174f0e6cb20" },
		{ "transfer_from", "0x3704ffe8fba161be0e994951751a5033b1462b918ff785c0a636be718dfdb68" },
		{ "name", "0x361458367e696363fbcc70777d07ebbd2394e89fd0adcaf147faccd1d294d60" },
		{ "symbol", "0x216b05c387bab9ac31918a3e61672f4618601f3c598a2f3f2710f37053e1ea4" },
		{ "decimals", "0x4c4fb1ab068f6039d5780c68dd0fa2f8742cceb3426d19667778ca7f3518a9" },
		{ "total_supply", "0x1557182e4359a1f0c6301278e8f5b35a776ab58d39892581e357578fb287836" },
		{ "totalSupply", "0x80aa9fdbfaf9615e4afc7f5f722e265daca5ccc655360fa5ccacf9c267936d" },
		{ "__default__", "0x0" },
		{ "__l1_default__", "0x0" },
	},
}

--------------------------------------------------------------------------------
-- ECDSA signature vectors
-- Cross-referenced from @scure/starknet test suite
-- Source: https://github.com/paulmillr/scure-starknet/blob/main/test/stark.test.ts
--------------------------------------------------------------------------------

TestVectors.ECDSA = {
	-- Private key -> public key derivation: { privateKey, expectedPubKeyX }
	publicKeys = {
		{
			privateKey = "0x1",
			pubKeyX = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
		},
		{
			privateKey = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F",
			pubKeyX = "0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf",
		},
		{
			privateKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
			pubKeyX = "0x499f65ae2f71d5298d2d88823b2e5e19596a71aac1984710479e406a002439",
		},
	},
	-- Signing vectors: { privateKey, messageHash, expectedR, expectedS }
	-- Vector set 1: from @scure/starknet test
	signatures = {
		-- Set 1, privkey_1 vectors
		{
			privateKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
			messageHash = "0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47",
			r = "0x5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2",
			s = "0x4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3",
		},
		{
			privateKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
			messageHash = "0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47a",
			r = "0x233b88c4578f0807b4a7480c8076eca5cfefa29980dd8e2af3c46a253490e9c",
			s = "0x28b055e825bc507349edfb944740a35c6f22d377443c34742c04e0d82278cf1",
		},
		{
			privateKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
			messageHash = "0x7465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47a1",
			r = "0xb6bee8010f96a723f6de06b5fa06e820418712439c93850dd4e9bde43ddf",
			s = "0x1a3d2bc954ed77e22986f507d68d18115fa543d1901f5b4620db98e2f6efd80",
		},
		-- Set 2, privkey_2 vectors
		{
			privateKey = "0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF",
			messageHash = "0x00",
			r = "0x443b6a567dfeae1c8c77dc589cdde204649f85ba45e54bead543299e5888233",
			s = "0x12bcacdadecfca0773945071b371adda1bc47fce319f80aa590b06d45a996f5",
		},
		{
			privateKey = "0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF",
			messageHash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F61",
			r = "0x78a73ac7f793e706e50871da2efc2f83c30852a90110cab71108ff6a3af864e",
			s = "0x49ec9e6aa783e7518ffc05ec054db3ddf2d8ad301e4ee790392841fa759431e",
		},
		{
			privateKey = "0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF",
			messageHash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C",
			r = "0x5864e5d2843d4469e70282042c7675e4fcb4b530d45dd6f02ae03c8d2f5431a",
			s = "0x2c512662f37585497683e2d98c655e098ad4504d41d3a3b17ad0f0f9db45ddb",
		},
		{
			privateKey = "0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF",
			messageHash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C1D",
			r = "0x7f313dc69e5f785a7071a9acc12a1294bce54d199a90b1ecdd39fd654c55190",
			s = "0x7a2902b67913c013557f0ea61902a1edc8539aa1321549bef9a47dbb9af0eba",
		},
		{
			privateKey = "0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF",
			messageHash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C1D00",
			r = "0x73bab8d7be901dc6bdba59f458c3ddeb4e0264657c60ff1b42a403d69e84718",
			s = "0x4cb6384d5b82bf873c87e02e11d32cefb1f10cc6d3d67895662d6c87c6df505",
		},
	},
}

--------------------------------------------------------------------------------
-- Transaction hash vectors
-- Cross-referenced from starknet.js / SNIP-8 spec
--------------------------------------------------------------------------------

TestVectors.TransactionHash = {
	-- V3 INVOKE transaction hash vectors
	invoke = {
		-- Test vector 1: Simple demo
		{
			params = {
				senderAddress = "0x12fd538",
				compiledCalldata = { "0x11", "0x26" },
				chainId = "0x31",
				nonce = "0x9",
				resourceBounds = {
					l1Gas = { maxAmount = "0x7c9", maxPricePerUnit = "0x1" },
					l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				},
			},
			expected = "0x713c8f6b968aa65dfd450eaf29511809bd08d10e1d24dea890916edf207f395",
		},
		-- Test vector 2: Sepolia multicall (16-element calldata)
		{
			params = {
				senderAddress = "0x3f6f3bc663aedc5285d6013cc3ffcbc4341d86ab488b8b68d297f8258793c41",
				compiledCalldata = {
					"0x2",
					"0x4c312760dfd17a954cdd09e76aa9f149f806d88ec3e402ffaf5c4926f568a42",
					"0x31aafc75f498fdfa7528880ad27246b4c15af4954f96228c9a132b328de1c92",
					"0x0",
					"0x6",
					"0x450703c32370cf7ffff540b9352e7ee4ad583af143a361155f2b485c0c39684",
					"0xb17d8a2731ba7ca1816631e6be14f0fc1b8390422d649fa27f0fbb0c91eea8",
					"0x6",
					"0x0",
					"0x6",
					"0x6333f10b24ed58cc33e9bac40b0d52e067e32a175a97ca9e2ce89fe2b002d82",
					"0x3",
					"0x602e89fe5703e5b093d13d0a81c9e6d213338dc15c59f4d3ff3542d1d7dfb7d",
					"0x20d621301bea11ffd9108af1d65847e9049412159294d0883585d4ad43ad61b",
					"0x276faadb842bfcbba834f3af948386a2eb694f7006e118ad6c80305791d3247",
					"0x613816405e6334ab420e53d4b38a0451cb2ebca2755171315958c87d303cf6",
				},
				chainId = "0x534e5f5345504f4c4941",
				nonce = "0x8a9",
				resourceBounds = {
					l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
					l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				},
			},
			expected = "0x6b68ec8759c56f2d9a4f7355019c0ba1450ca026dc61d0506dbad1d0f8070e5",
		},
		-- Test vector 3: Minimal (empty calldata)
		{
			params = {
				senderAddress = "0x1",
				compiledCalldata = {},
				chainId = "0x534e5f5345504f4c4941",
				nonce = "0x0",
				resourceBounds = {
					l1Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				},
			},
			expected = "0x81c846c1ddc1e68c081a731132dbd6748081423a8cb7ed698e61f9dbe3bd66",
		},
		-- Test vector 4: Non-zero tip + all gas types
		{
			params = {
				senderAddress = "0xabc123",
				compiledCalldata = { "0x1", "0x2", "0x3" },
				chainId = "0x534e5f4d41494e",
				nonce = "0x2a",
				tip = "0x123",
				resourceBounds = {
					l1Gas = { maxAmount = "0x2710", maxPricePerUnit = "0x174876e800" },
					l2Gas = { maxAmount = "0x1388", maxPricePerUnit = "0x3b9aca00" },
					l1DataGas = { maxAmount = "0x64", maxPricePerUnit = "0x5f5e100" },
				},
			},
			expected = "0x7eb1aea92dfdbad0e03246c3dade1b21b21e348ca66c6aa09bdc8d1cbad8c08",
		},
		-- Test vector 5: Paymaster + deploy data
		{
			params = {
				senderAddress = "0x12fd538",
				compiledCalldata = { "0x42", "0x43" },
				chainId = "0x534e5f5345504f4c4941",
				nonce = "0x1",
				paymasterData = { "0xaaa", "0xbbb" },
				accountDeploymentData = { "0xdead", "0xbeef" },
				resourceBounds = {
					l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
					l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				},
			},
			expected = "0x5ac1bb61673b66a1f3faf2f101ac157c5a72fef6a097de4e59d51f5fb2c5257",
		},
		-- Test vector 6: L2 DA mode
		{
			params = {
				senderAddress = "0x12fd538",
				compiledCalldata = { "0x1" },
				chainId = "0x534e5f5345504f4c4941",
				nonce = "0x0",
				nonceDataAvailabilityMode = 1,
				feeDataAvailabilityMode = 1,
				resourceBounds = {
					l1Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
					l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				},
			},
			expected = "0x6e126cf89d494a93eb29761aa558df6524e9a1a4bcf084f96c53766707aec5d",
		},
	},
}

--------------------------------------------------------------------------------
-- Account address vectors
-- Cross-referenced from starknet.js calculateContractAddressFromHash
--------------------------------------------------------------------------------

TestVectors.Account = {
	-- OZ class hash v0.11
	ozClassHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
	-- OZ class hash v0.14
	ozClassHash2 = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003",

	-- Private key -> public key -> address vectors
	-- Format: { privateKey, publicKeyX, addressOZ, addressOZ2 }
	addresses = {
		{
			privateKey = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
			publicKey = "0x499f65ae2f71d5298d2d88823b2e5e19596a71aac1984710479e406a002439",
			addressOZ = "0x76d427e4760e8a0947f747c98263827154aca2c999b288a2087cd9655e2008d",
			addressOZ2 = "0x38de74aab5907ad06a25dd88fafe0296a2ca303fedb8b37926edf15363aee67",
		},
		{
			privateKey = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F",
			publicKey = "0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf",
			addressOZ = "0x568f41175d86b1ea857a8daba89430ebe5b5da27c6848fa8234392151ea8b39",
			addressOZ2 = "0x365ff7fefa7c4a5e0c41e2c27aa55d35b6439fa891ad5b85da1cdffeb736f08",
		},
		{
			privateKey = "0x1",
			publicKey = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
			addressOZ = "0x2b5cea709ab25612f9d014a3312f1c6dbd988add3bf396c1866db1b03b09194",
			addressOZ2 = "0x4235a538f2315ca101e7260ff94997456428a1a7138b71ab335a423602400d8",
		},
	},

	-- Special case vectors: { publicKey, deployer, salt, classHash, expected }
	specialCases = {
		{
			publicKey = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
			deployer = "0x1234abcd",
			classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
			expected = "0x2fc571eae3a2def65072a216ed75275fcc7a54fe4e386500d5b74cf77028b44",
		},
		{
			publicKey = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
			salt = "0xdeadbeef",
			classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
			expected = "0x452c8719749629fcdd8a1fc541ac2b9108cbdb33a63095125c4eeedeec052c7",
		},
	},
}

--------------------------------------------------------------------------------
-- Constants vectors
-- Cross-referenced from starknet.js constants
--------------------------------------------------------------------------------

TestVectors.Constants = {
	-- Chain IDs (ASCII-encoded felts)
	SN_MAIN = "0x534e5f4d41494e",
	SN_SEPOLIA = "0x534e5f5345504f4c4941",
	-- Contract address prefix
	CONTRACT_ADDRESS_PREFIX = "0x535441524b4e45545f434f4e54524143545f41444452455353",
	-- Well-known token addresses on mainnet
	ETH_TOKEN_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
	STRK_TOKEN_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
	-- Curve constants
	STARK_PRIME = "0x800000000000011000000000000000000000000000000000000000000000001",
	CURVE_ORDER = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f",
	GENERATOR_X = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca",
	GENERATOR_Y = "0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f",
}

return TestVectors

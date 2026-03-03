--!strict
-- AvnuPaymaster: Pre-configured convenience layer for AVNU's paymaster service (SNIP-29)
-- Thin wrapper over PaymasterRpc with auto-selected endpoints, known token addresses,
-- and cached getSupportedTokens results.
--
-- Without apiKey: gasless mode (user pays in alt token)
-- With apiKey: gasfree/sponsored mode (game developer pays gas)

local PaymasterRpc = require("./PaymasterRpc")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- AVNU Endpoint URLs
--------------------------------------------------------------------------------

local AVNU_ENDPOINTS: { [string]: string } = {
	mainnet = "https://starknet.paymaster.avnu.fi",
	sepolia = "https://sepolia.paymaster.avnu.fi",
}

--------------------------------------------------------------------------------
-- Well-known token addresses per network
--------------------------------------------------------------------------------

export type TokenInfo = {
	symbol: string,
	address: string,
	decimals: number,
}

local KNOWN_TOKENS: { [string]: { [string]: TokenInfo } } = {
	mainnet = {
		ETH = {
			symbol = "ETH",
			address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			decimals = 18,
		},
		STRK = {
			symbol = "STRK",
			address = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
			decimals = 18,
		},
		USDC = {
			symbol = "USDC",
			address = "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8",
			decimals = 6,
		},
		USDT = {
			symbol = "USDT",
			address = "0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8",
			decimals = 6,
		},
	},
	sepolia = {
		ETH = {
			symbol = "ETH",
			address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			decimals = 18,
		},
		STRK = {
			symbol = "STRK",
			address = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
			decimals = 18,
		},
	},
}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type AvnuPaymasterConfig = {
	network: string, -- "mainnet" | "sepolia"
	apiKey: string?, -- AVNU paymaster API key (enables sponsored/gasfree mode)
	nodeUrl: string?, -- override the auto-selected AVNU URL
	retryAttempts: number?,
	retryDelay: number?,
	maxRequestsPerMinute: number?,
	tokenCacheTtl: number?, -- seconds to cache getSupportedTokens (default 300 = 5 min)
	-- Testing injection points
	_httpRequest: ((request: PaymasterRpc.HttpRequest) -> PaymasterRpc.HttpResponse)?,
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

export type AvnuPaymaster = {
	-- All PaymasterRpc methods (delegated)
	isAvailable: (self: AvnuPaymaster) -> PaymasterRpc.Promise<boolean>,
	getSupportedTokens: (self: AvnuPaymaster) -> PaymasterRpc.Promise<{ PaymasterRpc.TokenData }>,
	buildTypedData: (
		self: AvnuPaymaster,
		userAddress: string,
		calls: { PaymasterRpc.Call },
		gasTokenAddress: string,
		options: PaymasterRpc.BuildTypedDataOptions?
	) -> PaymasterRpc.Promise<PaymasterRpc.BuildTypedDataResult>,
	executeTransaction: (
		self: AvnuPaymaster,
		userAddress: string,
		typedData: any,
		signature: { string },
		options: PaymasterRpc.BuildTypedDataOptions?
	) -> PaymasterRpc.Promise<PaymasterRpc.ExecuteResult>,
	trackingIdToLatestHash: (
		self: AvnuPaymaster,
		trackingId: string
	) -> PaymasterRpc.Promise<PaymasterRpc.TrackingResult>,
	fetch: (self: AvnuPaymaster, method: string, params: any) -> PaymasterRpc.Promise<any>,
	getNodeUrl: (self: AvnuPaymaster) -> string,
	-- AVNU-specific methods
	getNetwork: (self: AvnuPaymaster) -> string,
	isSponsored: (self: AvnuPaymaster) -> boolean,
	getKnownTokens: (self: AvnuPaymaster) -> { [string]: TokenInfo },
	getTokenAddress: (self: AvnuPaymaster, symbol: string) -> string?,
	clearTokenCache: (self: AvnuPaymaster) -> (),
}

--------------------------------------------------------------------------------
-- AvnuPaymaster class
--------------------------------------------------------------------------------

local AvnuPaymasterClass = {}
AvnuPaymasterClass.__index = AvnuPaymasterClass

--- Create a new AVNU paymaster client.
--- @param config -- AvnuPaymasterConfig with network and optional apiKey
function AvnuPaymasterClass.new(config: AvnuPaymasterConfig): AvnuPaymaster
	local network = config.network
	if not network or network == "" then
		error(
			StarknetError.validation(
				"AvnuPaymaster: network is required ('mainnet' or 'sepolia')",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	-- Resolve endpoint URL
	local nodeUrl = config.nodeUrl
	if not nodeUrl or nodeUrl == "" then
		nodeUrl = AVNU_ENDPOINTS[network]
		if not nodeUrl then
			error(
				StarknetError.validation(
					`AvnuPaymaster: unknown network '{network}'. Use 'mainnet' or 'sepolia', or provide a custom nodeUrl.`,
					ErrorCodes.INVALID_ARGUMENT.code
				)
			)
		end
	end

	-- Build headers with API key if provided
	local headers: { [string]: string } = {}
	if config.apiKey and config.apiKey ~= "" then
		headers["x-paymaster-api-key"] = config.apiKey
	end

	-- Create underlying PaymasterRpc
	local paymasterConfig: PaymasterRpc.PaymasterConfig = {
		nodeUrl = nodeUrl :: string,
		headers = headers,
		retryAttempts = config.retryAttempts,
		retryDelay = config.retryDelay,
		maxRequestsPerMinute = config.maxRequestsPerMinute,
		_httpRequest = config._httpRequest,
		_sleep = config._sleep,
		_clock = config._clock,
	}

	local inner = PaymasterRpc.new(paymasterConfig)
	local clockFn = config._clock or os.clock

	local self = setmetatable({
		_inner = inner,
		_network = network,
		_apiKey = config.apiKey or "",
		_tokenCacheTtl = config.tokenCacheTtl or 300,
		_cachedTokens = nil :: { PaymasterRpc.TokenData }?,
		_cacheTimestamp = 0,
		_clock = clockFn,
	}, AvnuPaymasterClass)

	return self :: any
end

--------------------------------------------------------------------------------
-- AVNU-specific methods
--------------------------------------------------------------------------------

--- Get the configured network name.
function AvnuPaymasterClass:getNetwork(): string
	return self._network
end

--- Check if this paymaster is in sponsored/gasfree mode (API key provided).
function AvnuPaymasterClass:isSponsored(): boolean
	return self._apiKey ~= ""
end

--- Get known token addresses for the configured network.
--- Returns a table of symbol → TokenInfo.
function AvnuPaymasterClass:getKnownTokens(): { [string]: TokenInfo }
	local tokens = KNOWN_TOKENS[self._network]
	if not tokens then
		return {}
	end
	return table.clone(tokens)
end

--- Get the token address for a known symbol on the configured network.
--- Returns nil if the symbol is not known.
function AvnuPaymasterClass:getTokenAddress(symbol: string): string?
	local tokens = KNOWN_TOKENS[self._network]
	if not tokens then
		return nil
	end
	local info = tokens[symbol]
	if info then
		return info.address
	end
	return nil
end

--- Clear the cached getSupportedTokens result.
function AvnuPaymasterClass:clearTokenCache()
	self._cachedTokens = nil
	self._cacheTimestamp = 0
end

--------------------------------------------------------------------------------
-- Delegated PaymasterRpc methods
--------------------------------------------------------------------------------

--- Get the underlying paymaster endpoint URL.
function AvnuPaymasterClass:getNodeUrl(): string
	return self._inner:getNodeUrl()
end

--- Check if the paymaster is available.
function AvnuPaymasterClass:isAvailable(): any
	return self._inner:isAvailable()
end

--- Get supported tokens with caching.
--- Token lists rarely change, so results are cached for `tokenCacheTtl` seconds (default 300).
function AvnuPaymasterClass:getSupportedTokens(): any
	local now = self._clock()

	-- Return cached result if still fresh
	if self._cachedTokens and (now - self._cacheTimestamp) < self._tokenCacheTtl then
		-- Need to wrap in a Promise — get the Promise module from inner
		local innerAny = self._inner :: any
		if innerAny._PromiseModule then
			return innerAny._PromiseModule.resolve(self._cachedTokens)
		end
		-- In test mode (no PromiseModule), fall through to network call
	end

	-- Fetch from network and cache
	return self._inner:getSupportedTokens():andThen(function(tokens: { PaymasterRpc.TokenData })
		self._cachedTokens = tokens
		self._cacheTimestamp = self._clock()
		return tokens
	end)
end

--- Build typed data for a transaction.
function AvnuPaymasterClass:buildTypedData(
	userAddress: string,
	calls: { PaymasterRpc.Call },
	gasTokenAddress: string,
	options: PaymasterRpc.BuildTypedDataOptions?
): any
	return self._inner:buildTypedData(userAddress, calls, gasTokenAddress, options)
end

--- Execute a signed transaction through the paymaster.
function AvnuPaymasterClass:executeTransaction(
	userAddress: string,
	typedData: any,
	signature: { string },
	options: PaymasterRpc.BuildTypedDataOptions?
): any
	return self._inner:executeTransaction(userAddress, typedData, signature, options)
end

--- Map a tracking ID to the latest transaction hash.
function AvnuPaymasterClass:trackingIdToLatestHash(trackingId: string): any
	return self._inner:trackingIdToLatestHash(trackingId)
end

--- Raw JSON-RPC fetch.
function AvnuPaymasterClass:fetch(method: string, params: any): any
	return self._inner:fetch(method, params)
end

--------------------------------------------------------------------------------
-- Static: endpoint and token constants
--------------------------------------------------------------------------------

--- Get the AVNU paymaster endpoint URL for a network.
function AvnuPaymasterClass.getEndpoint(network: string): string?
	return AVNU_ENDPOINTS[network]
end

--- Get all known AVNU endpoints.
function AvnuPaymasterClass.getEndpoints(): { [string]: string }
	return table.clone(AVNU_ENDPOINTS)
end

--- Get all known token addresses for a network.
function AvnuPaymasterClass.getTokensForNetwork(network: string): { [string]: TokenInfo }
	local tokens = KNOWN_TOKENS[network]
	if not tokens then
		return {}
	end
	return table.clone(tokens)
end

return AvnuPaymasterClass

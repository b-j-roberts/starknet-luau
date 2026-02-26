--!strict
-- RpcTypes: Type definitions for Starknet JSON-RPC request/response objects
-- Follows the Starknet RPC 0.7+ specification

local RpcTypes = {}

--- Request priority levels for the queue
export type RequestPriority = "high" | "normal" | "low"

--- Configuration for the request queue
export type RequestQueueConfig = {
	maxQueueDepth: number?, -- max items before backpressure (default 100)
	maxBatchSize: number?, -- max items per JSON-RPC batch (default 20)
	enableBatching: boolean?, -- whether to batch read-only requests (default true)
}

--- Configuration for the nonce manager
export type NonceManagerConfig = {
	maxPendingNonces: number?, -- max concurrent pending nonces per address (default 10)
	autoResyncOnError: boolean?, -- auto re-sync on-chain on nonce failure (default true)
}

--- Configuration for the response cache
export type CacheConfig = {
	maxEntries: number?, -- max cached entries before LRU eviction (default 256)
	chainIdTTL: number?, -- TTL for chainId in seconds (default 0 = indefinite)
	specVersionTTL: number?, -- TTL for specVersion in seconds (default 0 = indefinite)
	blockNumberTTL: number?, -- TTL for blockNumber in seconds (default 10)
	blockTTL: number?, -- TTL for block methods in seconds (default 10)
	classHashTTL: number?, -- TTL for getClassHashAt in seconds (default 0 = indefinite)
	classTTL: number?, -- TTL for getClass/getClassAt in seconds (default 0 = indefinite)
	storageTTL: number?, -- TTL for getStorageAt in seconds (default 30)
	callTTL: number?, -- TTL for call in seconds (default 30)
}

--- Options for individual fetch calls
export type FetchOptions = {
	bypassCache: boolean?, -- skip cache lookup and storage for this request
}

--- Provider metrics snapshot
export type ProviderMetrics = {
	totalRequests: number,
	totalCompleted: number,
	totalFailed: number,
	totalBatched: number,
	totalDropped: number,
	currentQueueDepth: number,
	rateLimitTokens: number,
	rateLimitMax: number,
	batchesSent: number,
	cacheHits: number,
	cacheMisses: number,
	cacheEvictions: number,
	cacheSize: number,
	nonceReserved: number,
	nonceConfirmed: number,
	nonceRejected: number,
	nonceResyncs: number,
}

--- Configuration for creating an RpcProvider
export type RpcProviderConfig = {
	nodeUrl: string,
	headers: { [string]: string }?,
	maxRequestsPerMinute: number?,
	retryAttempts: number?,
	retryDelay: number?,
	enableQueue: boolean?,
	queueConfig: RequestQueueConfig?,
	enableCache: boolean?,
	cacheConfig: CacheConfig?,
	enableNonceManager: boolean?,
	nonceManagerConfig: NonceManagerConfig?,
	-- Internal overrides for testing (not part of public API)
	_httpRequest: ((request: HttpRequest) -> HttpResponse)?,
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
	_defer: ((fn: () -> ()) -> ())?,
}

--- HTTP request structure (mirrors HttpService:RequestAsync input)
export type HttpRequest = {
	Url: string,
	Method: string,
	Headers: { [string]: string },
	Body: string?,
}

--- HTTP response structure (mirrors HttpService:RequestAsync output)
export type HttpResponse = {
	StatusCode: number,
	Body: string,
	Headers: { [string]: string }?,
	Success: boolean,
}

--- JSON-RPC 2.0 request envelope
export type JsonRpcRequest = {
	jsonrpc: string,
	method: string,
	params: any,
	id: number,
}

--- JSON-RPC 2.0 response envelope
export type JsonRpcResponse = {
	jsonrpc: string,
	id: number,
	result: any?,
	error: JsonRpcError?,
}

--- JSON-RPC error object
export type JsonRpcError = {
	code: number,
	message: string,
	data: any?,
}

--- SDK error structure (structured errors with :is() method)
export type StarknetError = {
	_type: string,
	message: string,
	code: number?,
	data: any?,
	is: (self: StarknetError, errorType: string) -> boolean,
}

--- Request for starknet_call
export type CallRequest = {
	contract_address: string,
	entry_point_selector: string,
	calldata: { string },
}

--- Block ID tag
export type BlockId = {
	block_hash: string?,
	block_number: number?,
	block_tag: string?, -- "latest" | "pending"
}

--- Fee estimate result
export type FeeEstimate = {
	gas_consumed: string,
	gas_price: string,
	overall_fee: string,
	data_gas_consumed: string,
	data_gas_price: string,
	unit: string,
}

--- Transaction receipt
export type TransactionReceipt = {
	transaction_hash: string,
	actual_fee: { amount: string, unit: string },
	execution_status: string,
	finality_status: string,
	block_hash: string?,
	block_number: number?,
	events: { Event },
	revert_reason: string?,
	type: string?,
}

--- Transaction status
export type TransactionStatus = {
	finality_status: string,
	execution_status: string?,
}

--- Event from a transaction receipt or event filter
export type Event = {
	from_address: string,
	keys: { string },
	data: { string },
}

--- Event filter for starknet_getEvents
export type EventFilter = {
	from_block: BlockId?,
	to_block: BlockId?,
	address: string?,
	keys: { { string } }?,
	chunk_size: number?,
	continuation_token: string?,
}

--- Events response chunk
export type EventsChunk = {
	events: { EmittedEvent },
	continuation_token: string?,
}

--- Emitted event (includes block/tx context)
export type EmittedEvent = {
	from_address: string,
	keys: { string },
	data: { string },
	block_hash: string?,
	block_number: number?,
	transaction_hash: string?,
}

--- Resource bounds for V3 transactions
export type ResourceBounds = {
	l1_gas: { max_amount: string, max_price_per_unit: string },
	l2_gas: { max_amount: string, max_price_per_unit: string },
}

--- Invoke transaction V3 (for addInvokeTransaction)
export type InvokeTransactionV3 = {
	type: string,
	version: string,
	sender_address: string,
	calldata: { string },
	signature: { string },
	nonce: string,
	resource_bounds: ResourceBounds,
	tip: string,
	paymaster_data: { string },
	nonce_data_availability_mode: string,
	fee_data_availability_mode: string,
	account_deployment_data: { string },
}

--- Block with transaction hashes
export type Block = {
	block_hash: string?,
	parent_hash: string,
	block_number: number?,
	status: string?,
	new_root: string?,
	timestamp: number,
	sequencer_address: string?,
	transactions: { string },
	l1_gas_price: { price_in_wei: string, price_in_fri: string }?,
}

--- Full transaction object (returned by getBlockWithTxs, getTransactionByHash)
export type Transaction = {
	transaction_hash: string,
	type: string, -- "INVOKE" | "DECLARE" | "DEPLOY_ACCOUNT" | "L1_HANDLER"
	version: string,
	nonce: string?,
	sender_address: string?,
	calldata: { string }?,
	signature: { string }?,
	max_fee: string?,
	resource_bounds: ResourceBounds?,
	tip: string?,
	paymaster_data: { string }?,
	nonce_data_availability_mode: string?,
	fee_data_availability_mode: string?,
	account_deployment_data: { string }?,
	-- DECLARE-specific
	class_hash: string?,
	compiled_class_hash: string?,
	contract_address_salt: string?,
	constructor_calldata: { string }?,
	-- L1_HANDLER-specific
	contract_address: string?,
	entry_point_selector: string?,
}

--- Block with full transactions
export type BlockWithTxs = {
	block_hash: string?,
	parent_hash: string,
	block_number: number?,
	status: string?,
	new_root: string?,
	timestamp: number,
	sequencer_address: string?,
	transactions: { Transaction },
	l1_gas_price: { price_in_wei: string, price_in_fri: string }?,
}

--- Transaction receipt with hash (for getBlockWithReceipts)
export type TransactionWithReceipt = {
	transaction: Transaction,
	receipt: TransactionReceipt,
}

--- Block with transaction receipts
export type BlockWithReceipts = {
	block_hash: string?,
	parent_hash: string,
	block_number: number?,
	status: string?,
	new_root: string?,
	timestamp: number,
	sequencer_address: string?,
	transactions: { TransactionWithReceipt },
	l1_gas_price: { price_in_wei: string, price_in_fri: string }?,
}

--- Contract class definition (Sierra or legacy)
export type ContractClass = {
	-- Sierra class fields
	sierra_program: { string }?,
	contract_class_version: string?,
	entry_points_by_type: any?,
	abi: string?,
	-- Legacy class fields
	program: string?,
}

--- L1→L2 message for estimateMessageFee
export type MessageFromL1 = {
	from_address: string, -- L1 Ethereum address
	to_address: string, -- L2 Starknet contract address
	entry_point_selector: string,
	payload: { string },
}

--- Syncing status
export type SyncingStatus = {
	starting_block_hash: string?,
	starting_block_num: number?,
	current_block_hash: string?,
	current_block_num: number?,
	highest_block_hash: string?,
	highest_block_num: number?,
}

--- Options for waitForTransaction
export type WaitOptions = {
	retryInterval: number?,
	maxAttempts: number?,
}

--- Parsed event with decoded fields
export type ParsedEvent = {
	name: string,
	fields: { [string]: any },
	raw: EmittedEvent | Event,
}

--- Configuration for EventPoller
export type EventPollerConfig = {
	provider: any,
	filter: EventFilter,
	interval: number?, -- polling interval in seconds (default 10)
	onEvents: ((events: { EmittedEvent }) -> ())?,
	onError: ((err: any) -> ())?,
	-- Internal overrides for testing
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

--- Error type constants
RpcTypes.ErrorTypes = {
	RPC_ERROR = "RPC_ERROR",
	NETWORK_ERROR = "NETWORK_ERROR",
	RATE_LIMIT = "RATE_LIMIT",
	TIMEOUT = "TIMEOUT",
	INVALID_ARGUMENT = "INVALID_ARGUMENT",
}

return RpcTypes

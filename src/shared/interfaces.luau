--!strict
-- Shared interface types that exist to break circular module dependencies.
-- Defines structural contracts for Provider, Account, Signer, Paymaster, etc.
-- so that consumers can type parameters without importing concrete implementations.
-- This module has no runtime dependencies — only type definitions.

local Interfaces = {}

--------------------------------------------------------------------------------
-- Signer interfaces
--------------------------------------------------------------------------------

--- Minimal signer interface: only signHash.
--- Used by TransactionBuilder which only needs signing capability.
export type MinimalSigner = {
	signHash: (self: MinimalSigner, hash: buffer) -> { string },
}

--- Full signer interface with all StarkSigner methods.
--- Used by Account which needs both signing and public key derivation.
export type SignerInterface = {
	signHash: (self: SignerInterface, hash: buffer) -> { string },
	getPublicKeyHex: (self: SignerInterface) -> string,
	signRaw: (self: SignerInterface, msgHash: buffer) -> any, -- ECDSA.Signature
	getPubKey: (self: SignerInterface) -> any, -- AffinePoint
}

--------------------------------------------------------------------------------
-- Provider interface
--------------------------------------------------------------------------------

--- Provider interface: public methods that consumers call on RpcProvider.
--- Defined from the union of all methods used by Account, TransactionBuilder,
--- Contract, EventPoller, and SponsoredExecutor.
export type ProviderInterface = {
	getChainId: (self: ProviderInterface) -> any, -- Promise<string>
	getNonce: (self: ProviderInterface, contractAddress: string, blockId: any?) -> any, -- Promise<string>
	call: (self: ProviderInterface, request: any, blockId: any?) -> any, -- Promise<{string}>
	estimateFee: (self: ProviderInterface, transactions: { any }, simulationFlags: { string }?) -> any,
	addInvokeTransaction: (self: ProviderInterface, tx: any) -> any, -- Promise<InvokeResult>
	addDeployAccountTransaction: (self: ProviderInterface, tx: any) -> any, -- Promise<DeployAccountResult>
	waitForTransaction: (self: ProviderInterface, txHash: string, options: any?) -> any, -- Promise<TransactionReceipt>
	getEvents: (self: ProviderInterface, filter: any) -> any, -- Promise<EventsChunk>
	getAllEvents: (self: ProviderInterface, filter: any) -> any, -- Promise<{EmittedEvent}>
	getPromise: (self: ProviderInterface) -> any, -- Promise constructor
	getNonceManager: (self: ProviderInterface) -> any?, -- NonceManager or nil
	fetchSync: (self: ProviderInterface, method: string, params: any) -> any, -- Synchronous RPC call
}

--------------------------------------------------------------------------------
-- Account interface
--------------------------------------------------------------------------------

--- Account interface: methods that consumers (Contract, SponsoredExecutor) call on Account.
export type AccountInterface = {
	address: string,
	signer: SignerInterface,
	execute: (self: AccountInterface, calls: { any }, options: any?) -> any, -- Promise
	getNonce: (self: AccountInterface) -> any, -- Promise<string>
	estimateFee: (self: AccountInterface, calls: { any }) -> any, -- Promise
	getPublicKeyHex: (self: AccountInterface) -> string,
	hashMessage: (self: AccountInterface, typedData: any) -> string,
	signMessage: (self: AccountInterface, typedData: any) -> { string },
	executePaymaster: (self: AccountInterface, calls: { any }, paymasterDetails: any) -> any, -- Promise
	getProvider: (self: AccountInterface) -> ProviderInterface,
}

--------------------------------------------------------------------------------
-- Paymaster interface
--------------------------------------------------------------------------------

--- Paymaster interface: methods consumers call on PaymasterRpc.
export type PaymasterInterface = {
	isAvailable: (self: PaymasterInterface) -> any, -- Promise<boolean>
	getSupportedTokens: (self: PaymasterInterface) -> any, -- Promise<{TokenData}>
	buildTypedData: (
		self: PaymasterInterface,
		userAddress: string,
		calls: { any },
		gasTokenAddress: string,
		options: any?
	) -> any, -- Promise<BuildTypedDataResult>
	executeTransaction: (
		self: PaymasterInterface,
		userAddress: string,
		typedData: any,
		signature: { string },
		options: any?
	) -> any, -- Promise<ExecuteResult>
	trackingIdToLatestHash: (self: PaymasterInterface, trackingId: string) -> any, -- Promise<TrackingResult>
	getNodeUrl: (self: PaymasterInterface) -> string,
}

--- Paymaster details for Account paymaster methods (estimatePaymasterFee, executePaymaster, deployWithPaymaster).
export type PaymasterDetails = {
	paymaster: PaymasterInterface,
	feeMode: { mode: "sponsored" | "default", gasToken: string? },
	deploymentData: {
		classHash: string,
		calldata: { string },
		salt: string,
		unique: boolean?,
		sigdata: { string }?,
		version: number?,
	}?,
	gasTokenAddress: string?,
}

--------------------------------------------------------------------------------
-- Policy & Budget interfaces (used by SponsoredExecutor)
--------------------------------------------------------------------------------

--- Policy interface: validate player actions and record usage.
export type PolicyInterface = {
	validate: (self: PolicyInterface, playerId: number, calls: { any }) -> { allowed: boolean, reason: string? },
	recordUsage: (self: PolicyInterface, playerId: number) -> (),
}

--- Budget interface: manage per-player token budgets.
export type BudgetInterface = {
	canAfford: (self: BudgetInterface, playerId: number, cost: number) -> boolean,
	consumeTransaction: (self: BudgetInterface, playerId: number, cost: number) -> (),
	refundTransaction: (self: BudgetInterface, playerId: number, amount: number) -> (),
	calculateCost: (self: BudgetInterface, gasUsed: number?) -> number,
	getBalance: (self: BudgetInterface, playerId: number) -> number,
}

return Interfaces

--!strict
-- Constants: Network IDs, class hashes, and well-known token addresses for Starknet

local Constants = {}

--------------------------------------------------------------------------------
-- Chain IDs (ASCII-encoded felt values)
--------------------------------------------------------------------------------

-- Starknet Mainnet chain ID ("SN_MAIN")
Constants.SN_MAIN = "0x534e5f4d41494e"

-- Starknet Sepolia Testnet chain ID ("SN_SEPOLIA")
Constants.SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Class Hashes
--------------------------------------------------------------------------------

-- OpenZeppelin Account class hash (Cairo 1)
Constants.OZ_ACCOUNT_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

--------------------------------------------------------------------------------
-- Contract Address Computation
--------------------------------------------------------------------------------

-- "STARKNET_CONTRACT_ADDRESS" prefix as felt (ASCII encoding)
Constants.CONTRACT_ADDRESS_PREFIX = "0x535441524b4e45545f434f4e54524143545f41444452455353"

--------------------------------------------------------------------------------
-- Well-Known Token Addresses (same on Mainnet and Sepolia)
--------------------------------------------------------------------------------

-- Ether (ETH) ERC-20 token on Starknet
Constants.ETH_TOKEN_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

-- Starknet Token (STRK) ERC-20 on Starknet
Constants.STRK_TOKEN_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"

--------------------------------------------------------------------------------
-- Transaction Versions
--------------------------------------------------------------------------------

-- V3 INVOKE transaction version
Constants.INVOKE_TX_V3 = "0x3"

-- V3 DEPLOY_ACCOUNT transaction version
Constants.DEPLOY_ACCOUNT_TX_V3 = "0x3"

-- V3 DECLARE transaction version
Constants.DECLARE_TX_V3 = "0x3"

return Constants

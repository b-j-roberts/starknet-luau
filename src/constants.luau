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

-- Argent X Account class hash (Cairo 1, v0.4.0)
Constants.ARGENT_ACCOUNT_CLASS_HASH = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"

-- Braavos Account implementation class hash (v1.2.0)
Constants.BRAAVOS_ACCOUNT_CLASS_HASH = "0x03957f9f5a1cbfe918cedc2015c85200ca51a5f7506ecb6de98a5207b759bf8a"

-- Braavos Base Account class hash (used for address computation, v1.2.0)
Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH = "0x03d16c7a9a60b0593bd202f660a28c5d76e0403601d9ccc7e4fa253b6a70c201"

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

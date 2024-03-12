import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "hardhat-gas-reporter"
import "dotenv/config"

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000
            }
        }
    },
    defaultNetwork: 'hardhat',
    networks: {
        hardhat: {
            mining: {
                auto: true,
                interval: 1000
            }
        },
        sepolia: {
            accounts: [process.env.PRIVATE_KEY!],
            url: 'https://sepolia.infura.io/v3/569cee6284754b9e86ff2e5e55a0dc22',
            chainId: 11155111
        },
        goerli: {
            url: 'https://goerli.infura.io/v3/ccee76eabbf944f493b7c8b3d4b063e9',
            chainId: 5,
            accounts: [process.env.PRIVATE_KEY!],
        },
        mainnet: {
            accounts: [process.env.PRIVATE_KEY!],
            url: 'https://mainnet.infura.io/v3/ccee76eabbf944f493b7c8b3d4b063e9',
            chainId: 1
        }
    },
    gasReporter: {
        enabled: true,
        coinmarketcap: process.env.CMC_API_KEY,
        outputFile: 'gasReport.txt'
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_KEY
    }
};

export default config;

import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "hardhat-gas-reporter"
import "dotenv/config"

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.18",
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
        }
    },
    gasReporter: {
        enabled: true,
        coinmarketcap: process.env.CMC_API_KEY,
        outputFile: 'gasReports'
    },
};

export default config;

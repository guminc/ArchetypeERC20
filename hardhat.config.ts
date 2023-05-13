import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
    solidity: "0.8.18",
    defaultNetwork: 'hardhat',
    networks: {
        hardhat: {
            mining: {
                auto: true,
                interval: 1000
            }
        }
    }
};

export default config;

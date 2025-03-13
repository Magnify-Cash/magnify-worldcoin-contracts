# magnify-worldcoin-contracts

Smart contract development repository for Magnify's Worldcoin integration.

## Prerequisites

- [Node.js](https://nodejs.org/) (v20 or higher)
- [pnpm](https://pnpm.io/) package manager

## Setup

1. Install dependencies:
```bash
pnpm install
```

2. Configure environment variables:
   - Copy the `.env.example` file to `.env`
   - Fill in the required environment variables
```bash
cp .env.example .env
```

## Development

### Local Blockchain
To start a local Hardhat network:
```bash
npx hardhat node
```

### Running Scripts
To execute a deployment or other script:
```bash
npx hardhat run <script-path> --network <network-name>
```

Example:
```bash
npx hardhat run scripts/deploy-v3-localhost.ts --network localhost
```

### Testing
Run the test suite:
```bash
npx hardhat test
```

## License

This project is licensed under the MIT License.

---
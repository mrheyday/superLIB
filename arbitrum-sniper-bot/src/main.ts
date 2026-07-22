import { BigNumber, ethers } from 'ethers';
import { getTokens } from './tokens';
import { ExecutionBridge } from './bridge';
import { encodePath, calculateMinimumOutput, validatePath } from './uniswap';
import { provider, signer, DEADLINE } from './config';
import { Logger } from './logger';

interface OpportunityParams {
  tokenIn: string;
  tokenOut: string;
  amountIn: BigNumber;
  path: Buffer;
  minAmountOut: BigNumber;
  deadline: number;
  estimatedProfit: BigNumber;
}

const logger = new Logger('SniperBot');

interface Config {
  sniperSearcherAddress: string;
  flashLoanReceiverAddress: string;
  delegatedExecutorAddress: string;
  swapAmount: BigNumber;
  maxRetries: number;
  retryDelayMs: number;
}

class SniperBot {
  private bridge: ExecutionBridge;
  private config: Config;

  constructor(config: Config) {
    this.config = config;
    this.bridge = new ExecutionBridge({
      sniperSearcherAddress: config.sniperSearcherAddress,
      flashLoanReceiverAddress: config.flashLoanReceiverAddress,
      delegatedExecutorAddress: config.delegatedExecutorAddress,
    });
  }

  /**
   * Main execution loop
   */
  async run(): Promise<void> {
    logger.info('Starting Arbitrum Sniper Bot');

    try {
      // Verify setup
      await this.verifySetup();

      // Detect pool
      logger.info('Detecting latest Uniswap V3 pool...');
      const { Token0, Token1 } = await getTokens();

      if (!Token0 || !Token1) {
        throw new Error('Failed to detect tokens from pool');
      }

      const tokenFrom = Token0.token;
      const tokenTo = Token1.token;
      const walletAddress = await signer.getAddress();

      logger.info(`Pool detected: ${tokenFrom.symbol} → ${tokenTo.symbol}`);

      // Validate wallet has sufficient balance
      const walletBalance = await provider.getBalance(walletAddress);
      logger.info(`Wallet balance: ${ethers.utils.formatEther(walletBalance)} ETH`);

      const tokenBalance = await Token0.contract.balanceOf(walletAddress);
      logger.info(
        `Token balance: ${ethers.utils.formatUnits(tokenBalance, tokenFrom.decimals)} ${tokenFrom.symbol}`
      );

      // Calculate quote (simplified for demo)
      logger.info('Calculating optimal swap route...');

      // For demo, use a fixed output ratio (1:1 simplified, real implementation would use pool math)
      // In production, use Uniswap V3's quoter contract
      const quotedAmount = this.config.swapAmount.mul(95).div(100); // 95% output (5% slippage buffer)
      const estimatedOutputRaw = quotedAmount;
      const minOutput = calculateMinimumOutput(estimatedOutputRaw, 0.5);
      const estimatedProfit = estimatedOutputRaw.sub(this.config.swapAmount);

      logger.info(
        `Route calculated: ${ethers.utils.formatUnits(estimatedOutputRaw, tokenTo.decimals)} ${tokenTo.symbol}`
      );
      logger.info(
        `Estimated profit: ${ethers.utils.formatUnits(estimatedProfit, tokenTo.decimals)} ${tokenTo.symbol}`
      );

      // Encode swap path
      const path = encodePath(
        [tokenFrom.address, tokenTo.address],
        [3000] // 0.3% fee tier
      );

      if (!validatePath([tokenFrom.address, tokenTo.address], [3000])) {
        throw new Error('Invalid swap path');
      }

      // Execute via bridge
      logger.info('Executing swap via execution bridge...');
      const result = await this.executeWithRetry({
        tokenIn: tokenFrom.address,
        tokenOut: tokenTo.address,
        amountIn: this.config.swapAmount,
        path,
        minAmountOut: minOutput,
        deadline: DEADLINE,
        estimatedProfit,
      });

      if (!result.success) {
        throw new Error(`Execution failed: ${result.error}`);
      }

      logger.info(`✓ Swap successful!`);
      logger.info(`  Mode: ${result.mode}`);
      logger.info(`  Tx: ${result.txHash}`);
      logger.info(`  Gas: ${result.gasUsed?.toString()}`);
      logger.info(`  Profit: ${ethers.utils.formatUnits(result.profit || 0, 18)}`);
    } catch (error) {
      logger.error(`Bot failed: ${error instanceof Error ? error.message : String(error)}`);
      process.exit(1);
    }
  }

  /**
   * Execute with retry logic
   */
  private async executeWithRetry(opportunity: OpportunityParams) {
    let lastError: Error | undefined;

    for (let attempt = 1; attempt <= this.config.maxRetries; attempt++) {
      try {
        logger.info(`Execution attempt ${attempt}/${this.config.maxRetries}`);
        const result = await this.bridge.executeOptimal(opportunity);

        if (result.success) {
          return result;
        }

        lastError = new Error(result.error);
        logger.warn(`Attempt ${attempt} failed: ${result.error}`);

        if (attempt < this.config.maxRetries) {
          logger.info(`Retrying in ${this.config.retryDelayMs}ms...`);
          await new Promise((resolve) => setTimeout(resolve, this.config.retryDelayMs));
        }
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        logger.error(`Attempt ${attempt} error: ${lastError.message}`);

        if (attempt < this.config.maxRetries) {
          await new Promise((resolve) => setTimeout(resolve, this.config.retryDelayMs));
        }
      }
    }

    throw lastError || new Error('Execution failed after all retries');
  }

  /**
   * Verify bot setup
   */
  private async verifySetup(): Promise<void> {
    logger.info('Verifying setup...');

    // Check RPC connection
    const blockNumber = await provider.getBlockNumber();
    logger.info(`✓ RPC connected (block ${blockNumber})`);

    // Check wallet
    const walletAddress = await signer.getAddress();
    logger.info(`✓ Wallet: ${walletAddress}`);

    // Check execution contracts
    const stats = await this.bridge.getExecutionStats();
    logger.info(`✓ Direct mode: ${stats.directReady ? 'ready' : 'not ready'}`);
    logger.info(`✓ Flash loan: ${stats.flashLoanReady ? 'ready' : 'not ready'}`);
    logger.info(`✓ EIP-7702: ${stats.eip7702Ready ? 'ready' : 'not ready'}`);
  }
}

/**
 * Main entry point
 */
async function main() {
  // Load config
  if (
    !process.env.SNIPER_SEARCHER_ADDRESS ||
    !process.env.FLASH_LOAN_RECEIVER_ADDRESS ||
    !process.env.DELEGATED_EXECUTOR_ADDRESS
  ) {
    logger.error('Missing contract addresses in environment variables');
    process.exit(1);
  }

  const swapAmount = process.argv[2]
    ? ethers.utils.parseUnits(process.argv[2], 18)
    : ethers.utils.parseUnits('0.001', 18);

  const config: Config = {
    sniperSearcherAddress: process.env.SNIPER_SEARCHER_ADDRESS,
    flashLoanReceiverAddress: process.env.FLASH_LOAN_RECEIVER_ADDRESS,
    delegatedExecutorAddress: process.env.DELEGATED_EXECUTOR_ADDRESS,
    swapAmount,
    maxRetries: 3,
    retryDelayMs: 2000,
  };

  const bot = new SniperBot(config);
  await bot.run();
}

main().catch((error) => {
  logger.error(`Fatal error: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});

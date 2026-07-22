import { BigNumber, ethers, Signer } from 'ethers';
import { signer } from './config';

interface FlashLoanParams {
  token: string;
  amount: BigNumber;
  swapPath: Buffer;
  minAmountOut: BigNumber;
}

interface FlashLoanResult {
  success: boolean;
  txHash?: string;
  profit?: BigNumber;
  error?: string;
  gasUsed?: BigNumber;
}

const FLASH_LOAN_RECEIVER_ABI = [
  'function initiateFlashLoan(address token, uint256 amount, bytes calldata swapPath, uint256 minAmountOut) external',
  'function withdraw(address token, address to, uint256 amount) external',
  'function getBalance(address token) external view returns (uint256)',
];

// Aave V3 Lending Pool on Arbitrum: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
// Used in FlashLoanReceiver contract deployment

/**
 * Flash Loan Executor
 * Executes arbitrage using Aave flash loans (0% interest, only fee paid)
 *
 * Flow:
 * 1. Bot initiates flash loan
 * 2. Aave transfers tokens to receiver
 * 3. Receiver executes arbitrage swap
 * 4. Receiver repays loan + 0.09% fee
 * 5. Profit extracted to wallet
 */
export class FlashLoanExecutor {
  private receiver: ethers.Contract;
  private executorSigner: Signer;

  constructor(receiverAddress: string, executorSigner?: Signer) {
    this.executorSigner = executorSigner || signer;
    this.receiver = new ethers.Contract(
      receiverAddress,
      FLASH_LOAN_RECEIVER_ABI,
      this.executorSigner
    );
  }

  /**
   * Execute arbitrage using flash loan
   * @param params Flash loan parameters
   * @returns Execution result with profit
   */
  async executeFlashLoanArbitrage(params: FlashLoanParams): Promise<FlashLoanResult> {
    try {
      console.log(`\n⚡ Initiating flash loan arbitrage...`);
      console.log(`  Token: ${params.token}`);
      console.log(`  Borrow amount: ${ethers.utils.formatUnits(params.amount, 18)}`);
      console.log(`  Min output: ${ethers.utils.formatUnits(params.minAmountOut, 6)}`);
      console.log(`  Fee: 0.09% (paid on repayment)`);

      // Estimate gas
      const gasEstimate = await this.estimateFlashLoanGas(params);
      console.log(`  Gas estimate: ${gasEstimate.toString()}`);

      // Initiate flash loan
      const tx = await this.receiver.initiateFlashLoan(
        params.token,
        params.amount,
        params.swapPath,
        params.minAmountOut,
        {
          gasLimit: gasEstimate.mul(115).div(100), // 15% buffer
        }
      );

      console.log(`✋ Flash loan initiated: ${tx.hash}`);

      // Wait for confirmation
      const receipt = await tx.wait(3); // Wait for 3 confirmations

      if (!receipt) {
        return {
          success: false,
          error: 'Flash loan failed - no receipt',
        };
      }

      console.log(`✅ Flash loan completed in block ${receipt.blockNumber}`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);

      // Check profit
      const profit = await this.getProfitEstimate(params);
      if (profit.gt(0)) {
        console.log(`   💰 Profit: ${ethers.utils.formatUnits(profit, 18)}`);
      }

      return {
        success: true,
        txHash: tx.hash,
        profit: profit,
        gasUsed: receipt.gasUsed,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`❌ Flash loan failed: ${errorMsg}`);

      return {
        success: false,
        error: errorMsg,
      };
    }
  }

  /**
   * Execute multiple flash loans in sequence
   * @param loanBatches Array of flash loan parameter sets
   */
  async executeBatchFlashLoans(loanBatches: FlashLoanParams[]): Promise<FlashLoanResult[]> {
    console.log(`\n⚡ Executing batch flash loans (${loanBatches.length} loans)...`);
    const results: FlashLoanResult[] = [];

    for (let i = 0; i < loanBatches.length; i++) {
      console.log(`\n[${i + 1}/${loanBatches.length}]`);
      const result = await this.executeFlashLoanArbitrage(loanBatches[i]);
      results.push(result);

      // Small delay between loans
      if (i < loanBatches.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    const successCount = results.filter((r) => r.success).length;
    const totalProfit = results
      .filter((r) => r.profit)
      .reduce((sum, r) => sum.add(r.profit!), BigNumber.from(0));

    console.log(`\n📊 Batch Results:`);
    console.log(`   Successful: ${successCount}/${loanBatches.length}`);
    console.log(`   Total profit: ${ethers.utils.formatUnits(totalProfit, 18)}`);

    return results;
  }

  /**
   * Withdraw profit from flash loan receiver
   * @param token Token to withdraw
   * @param to Recipient address
   * @param amount Amount to withdraw (0 = all)
   */
  async withdraw(token: string, to: string, amount?: BigNumber): Promise<FlashLoanResult> {
    try {
      console.log(`\n💸 Withdrawing from flash loan receiver...`);

      const withdrawAmount = amount || (await this.getBalance(token));
      console.log(`  Token: ${token}`);
      console.log(`  Amount: ${ethers.utils.formatUnits(withdrawAmount, 18)}`);

      const tx = await this.receiver.withdraw(token, to, withdrawAmount);
      console.log(`✋ Withdrawal initiated: ${tx.hash}`);

      const receipt = await tx.wait(3);

      if (!receipt) {
        return {
          success: false,
          error: 'Withdrawal failed',
        };
      }

      console.log(`✅ Withdrawn successfully`);
      return {
        success: true,
        txHash: tx.hash,
        gasUsed: receipt.gasUsed,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`❌ Withdrawal failed: ${errorMsg}`);
      return {
        success: false,
        error: errorMsg,
      };
    }
  }

  /**
   * Check balance in flash loan receiver
   */
  async getBalance(token: string): Promise<BigNumber> {
    try {
      const balance = await this.receiver.getBalance(token);
      return BigNumber.from(balance);
    } catch (error) {
      console.error('Failed to get balance:', error);
      return BigNumber.from(0);
    }
  }

  /**
   * Get receiver contract address
   */
  getReceiverAddress(): string {
    return this.receiver.address;
  }

  /**
   * Estimate profit from flash loan arbitrage
   * profit = outputAmount - loanAmount - fee
   * where fee = loanAmount * 0.0009 (0.09%)
   */
  private async getProfitEstimate(params: FlashLoanParams): Promise<BigNumber> {
    const fee = params.amount.mul(9).div(10000); // 0.09% fee
    const totalCost = params.amount.add(fee);

    // Estimate: if we get at least minAmountOut, profit is:
    return params.minAmountOut.sub(totalCost).gt(0)
      ? params.minAmountOut.sub(totalCost)
      : BigNumber.from(0);
  }

  /**
   * Estimate gas for flash loan
   */
  private async estimateFlashLoanGas(params: FlashLoanParams): Promise<BigNumber> {
    try {
      const gasEstimate = await this.receiver.estimateGas.initiateFlashLoan(
        params.token,
        params.amount,
        params.swapPath,
        params.minAmountOut
      );
      return gasEstimate;
    } catch (error) {
      console.warn('Gas estimation failed, using default', error);
      return BigNumber.from('500000'); // Conservative default for flash loans
    }
  }
}

/**
 * Flash Loan Helper Functions
 */

/**
 * Calculate Aave flash loan fee
 * Fee = amount × 0.09% (0.0009)
 */
export function calculateFlashLoanFee(amount: BigNumber): BigNumber {
  return amount.mul(9).div(10000);
}

/**
 * Calculate break-even price for flash loan arbitrage
 * breakEvenPrice = (loanAmount + fee) / outputTokens
 */
export function calculateBreakEvenPrice(
  loanAmount: BigNumber,
  expectedOutput: BigNumber,
  outputDecimals: number = 18
): number {
  const fee = calculateFlashLoanFee(loanAmount);
  const totalCost = loanAmount.add(fee);
  const breakEven = totalCost.div(expectedOutput);
  return parseFloat(ethers.utils.formatUnits(breakEven, outputDecimals));
}

/**
 * Calculate max borrow amount given gas budget
 * maxBorrow = gasbudget / (gasPricePerBorrow + 0.09% fee cost)
 */
export function calculateMaxBorrowAmount(
  gasBudgetWei: BigNumber,
  gasPriceWei: BigNumber
): BigNumber {
  // Calculate max borrow given gas budget
  const maxFromBudget = gasBudgetWei.div(gasPriceWei);

  // Fee impact: for every 1 token borrowed, 0.0009 is paid as fee
  // Effective cost = 1.0009 per token
  return maxFromBudget.mul(10000).div(10009);
}

export default FlashLoanExecutor;

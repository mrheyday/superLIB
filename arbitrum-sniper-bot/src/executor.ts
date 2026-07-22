import { BigNumber, ethers, Signer } from 'ethers';
import { signer } from './config';

interface SwapParams {
  tokenIn: string;
  amountIn: BigNumber;
  path: Buffer;
  minAmountOut: BigNumber;
  deadline?: number;
}

interface ExecutionResult {
  success: boolean;
  txHash?: string;
  amountOut?: BigNumber;
  error?: string;
  gasUsed?: BigNumber;
}

const SNIPER_SEARCHER_ABI = [
  'function executeSwap(address tokenIn, uint256 amountIn, bytes calldata path, uint256 minAmountOut) external returns (uint256)',
  'function executeSwapWithDeadline(address tokenIn, uint256 amountIn, bytes calldata path, uint256 minAmountOut, uint256 deadline) external returns (uint256)',
  'function withdraw(address token, address to, uint256 amount) external',
  'function getBalance(address token) external view returns (uint256)',
];

export class SniperExecutor {
  private searcher: ethers.Contract;
  private executorSigner: Signer;

  constructor(searcherAddress: string, executorSigner?: Signer) {
    this.executorSigner = executorSigner || signer;
    this.searcher = new ethers.Contract(searcherAddress, SNIPER_SEARCHER_ABI, this.executorSigner);
  }

  /**
   * Execute swap through SniperSearcher contract
   */
  async executeSwap(params: SwapParams): Promise<ExecutionResult> {
    try {
      console.log(`\n📊 Executing swap...`);
      console.log(`  Input: ${ethers.utils.formatUnits(params.amountIn, 18)} tokens`);
      console.log(`  Min output: ${ethers.utils.formatUnits(params.minAmountOut, 6)}`);

      // Estimate gas
      const gasEstimate = await this.estimateSwapGas(params);
      console.log(`  Gas estimate: ${gasEstimate.toString()}`);

      // Execute swap
      const tx = await this.searcher.executeSwap(
        params.tokenIn,
        params.amountIn,
        params.path,
        params.minAmountOut,
        {
          gasLimit: gasEstimate.mul(110).div(100), // 10% buffer
        }
      );

      console.log(`✋ Transaction sent: ${tx.hash}`);

      // Wait for confirmation
      const receipt = await tx.wait(3); // Wait for 3 confirmations

      if (!receipt) {
        return {
          success: false,
          error: 'Transaction failed - no receipt',
        };
      }

      console.log(`✅ Confirmed in block ${receipt.blockNumber}`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);

      return {
        success: true,
        txHash: tx.hash,
        gasUsed: receipt.gasUsed,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`❌ Swap failed: ${errorMsg}`);

      return {
        success: false,
        error: errorMsg,
      };
    }
  }

  /**
   * Execute swap with custom deadline
   */
  async executeSwapWithDeadline(
    params: SwapParams & { deadline: number }
  ): Promise<ExecutionResult> {
    try {
      console.log(
        `\n📊 Executing swap with deadline ${new Date(params.deadline * 1000).toISOString()}...`
      );

      const gasEstimate = await this.estimateSwapGasWithDeadline(params);
      console.log(`  Gas estimate: ${gasEstimate.toString()}`);

      const tx = await this.searcher.executeSwapWithDeadline(
        params.tokenIn,
        params.amountIn,
        params.path,
        params.minAmountOut,
        params.deadline,
        {
          gasLimit: gasEstimate.mul(110).div(100),
        }
      );

      console.log(`✋ Transaction sent: ${tx.hash}`);

      const receipt = await tx.wait(3);

      if (!receipt) {
        return {
          success: false,
          error: 'Transaction failed',
        };
      }

      console.log(`✅ Confirmed in block ${receipt.blockNumber}`);
      return {
        success: true,
        txHash: tx.hash,
        gasUsed: receipt.gasUsed,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`❌ Swap failed: ${errorMsg}`);
      return {
        success: false,
        error: errorMsg,
      };
    }
  }

  /**
   * Withdraw tokens from searcher contract
   */
  async withdraw(token: string, to: string, amount?: BigNumber): Promise<ExecutionResult> {
    try {
      console.log(`\n💸 Withdrawing from searcher...`);

      const withdrawAmount = amount || (await this.getBalance(token));
      console.log(`  Token: ${token}`);
      console.log(`  Amount: ${ethers.utils.formatUnits(withdrawAmount, 18)}`);
      console.log(`  To: ${to}`);

      const tx = await this.searcher.withdraw(token, to, withdrawAmount);
      console.log(`✋ Transaction sent: ${tx.hash}`);

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
   * Withdraw multiple tokens at once
   */
  async withdrawAll(tokens: string[], to: string): Promise<ExecutionResult> {
    try {
      console.log(`\n💸 Withdrawing ${tokens.length} tokens...`);

      const tx = await this.searcher.withdrawAll(tokens, to);
      console.log(`✋ Transaction sent: ${tx.hash}`);

      const receipt = await tx.wait(3);

      if (!receipt) {
        return {
          success: false,
          error: 'Multi-withdrawal failed',
        };
      }

      console.log(`✅ All tokens withdrawn`);
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
   * Check balance of token in searcher
   */
  async getBalance(token: string): Promise<BigNumber> {
    try {
      const balance = await this.searcher.getBalance(token);
      return BigNumber.from(balance);
    } catch (error) {
      console.error('Failed to get balance:', error);
      return BigNumber.from(0);
    }
  }

  /**
   * Estimate gas for swap
   */
  private async estimateSwapGas(params: SwapParams): Promise<BigNumber> {
    try {
      const gasEstimate = await this.searcher.estimateGas.executeSwap(
        params.tokenIn,
        params.amountIn,
        params.path,
        params.minAmountOut
      );
      return gasEstimate;
    } catch (error) {
      console.warn('Gas estimation failed, using default', error);
      return BigNumber.from('2000000');
    }
  }

  /**
   * Estimate gas for swap with deadline
   */
  private async estimateSwapGasWithDeadline(
    params: SwapParams & { deadline: number }
  ): Promise<BigNumber> {
    try {
      const gasEstimate = await this.searcher.estimateGas.executeSwapWithDeadline(
        params.tokenIn,
        params.amountIn,
        params.path,
        params.minAmountOut,
        params.deadline
      );
      return gasEstimate;
    } catch (error) {
      console.warn('Gas estimation failed, using default', error);
      return BigNumber.from('2000000');
    }
  }

  /**
   * Get searcher address
   */
  getSearcherAddress(): string {
    return this.searcher.address;
  }
}

export default SniperExecutor;

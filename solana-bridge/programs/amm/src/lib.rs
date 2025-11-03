use anchor_lang::prelude::*;

pub mod instructions;
pub mod state;
pub mod math;
pub mod errors;

use instructions::*;

declare_id!("11111111111111111111111111111111");

#[program]
pub mod amm {
    use super::*;

    pub fn initialize_pool(
        ctx: Context<InitializePool>,
        amount_a: u64,
        amount_b: u64,
        amplification: u64,
    ) -> Result<()> {
        instructions::initialize::handler(ctx, amount_a, amount_b, amplification)
    }

    pub fn swap(
        ctx: Context<Swap>,
        amount_in: u64,
        min_amount_out: u64,
    ) -> Result<()> {
        instructions::swap::handler(ctx, amount_in, min_amount_out)
    }
}

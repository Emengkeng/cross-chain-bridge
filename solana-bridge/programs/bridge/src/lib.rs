use anchor_lang::prelude::*;

pub mod instructions;
pub mod state;
pub mod verification;

use instructions::*;

declare_id!("22222222222222222222222222222222"); // Placeholder

#[program]
pub mod bridge {
    use super::*;

    pub fn initialize_bridge(ctx: Context<InitializeBridge>) -> Result<()> {
        instructions::init_bridge::handler(ctx)
    }

    pub fn deposit(
        ctx: Context<Deposit>,
        amount: u64,
        recipient: [u8; 32],
    ) -> Result<()> {
        instructions::deposit::handler(ctx, amount, recipient)
    }

    pub fn withdraw(
        ctx: Context<Withdraw>,
        vaa: Vec<u8>,
    ) -> Result<()> {
        instructions::withdraw::handler(ctx, vaa)
    }
}

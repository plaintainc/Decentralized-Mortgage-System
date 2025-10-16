Loan Interest Escrow System

## Overview
Enhanced the Decentralized Mortgage System with an independent Loan Interest Escrow feature, allowing borrowers to pre-deposit funds for automatic loan payments. This reduces payment friction, improves loan performance tracking, and provides borrowers with better payment management tools.

## Technical Implementation

### Key Functions Added:
- `deposit-to-escrow`: Allows borrowers to deposit STX tokens into escrow
- `withdraw-from-escrow`: Enables borrowers to withdraw unused escrow funds
- `make-escrow-payment`: Processes automatic payments from escrow to lender
- `enable-auto-pay`/`disable-auto-pay`: Controls automatic payment functionality

### Key Data Structures:
- `loan-escrow` map: Tracks escrow balance, totals, and auto-pay settings per loan
- `escrow-transactions` map: Maintains detailed transaction history for each loan
- New error constants: `err-escrow-insufficient` and `err-escrow-overpayment`

### Read-Only Functions:
- `get-escrow-balance`: Returns current escrow balance for a loan
- `can-make-escrow-payment`: Checks if automatic payment is possible
- `calculate-escrow-coverage`: Shows how many months of payments are covered
- `get-escrow-activity-summary`: Comprehensive escrow status overview

## Testing & Validation
- ✅ Contract passes `clarinet check` with minor warnings
- ✅ All npm tests successful
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Clarity v3 compliant with proper error handling
- ✅ Independent feature with no cross-contract dependencies

## Security Features
- Borrower-only access controls for escrow operations
- Comprehensive balance validations before transfers
- Detailed transaction logging for audit trails
- Auto-pay safety checks to prevent unauthorized payments
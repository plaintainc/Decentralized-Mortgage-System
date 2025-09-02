# 🏠 Decentralized Mortgage System

A blockchain-based mortgage system built on Stacks that enables peer-to-peer mortgage lending without traditional financial intermediaries.

## 🌟 Features

- 📋 **Mortgage Applications**: Borrowers can create mortgage requests with collateral
- 💰 **Direct Lending**: Lenders can fund mortgages directly
- 📊 **Payment Tracking**: Automated monthly payment processing
- 🔒 **Collateral Management**: Secure collateral handling and liquidation
- ⚡ **Smart Liquidation**: Automatic liquidation for defaulted loans
- 📈 **Loan Analytics**: Track loan performance and statistics

## 🚀 Quick Start

### For Borrowers

1. **Create Mortgage Request**
   ```clarity
   (contract-call? .decentralized-mortgage-system create-mortgage-request 
     u1000000     ;; amount (1M microSTX)
     u500         ;; interest rate (5%)
     u8640        ;; term in blocks (~60 days)
     u1200000)    ;; collateral amount
   ```

2. **Make Payments**
   ```clarity
   (contract-call? .decentralized-mortgage-system make-payment 
     u1           ;; loan ID
     u50000)      ;; payment amount
   ```

### For Lenders

1. **Fund a Mortgage**
   ```clarity
   (contract-call? .decentralized-mortgage-system fund-mortgage u1)
   ```

2. **Liquidate Defaulted Loan**
   ```clarity
   (contract-call? .decentralized-mortgage-system liquidate-loan u1)
   ```

## 📖 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create-mortgage-request` | 📝 Create new mortgage application | amount, interest-rate, term-blocks, collateral-amount |
| `fund-mortgage` | 💵 Fund an approved mortgage | loan-id |
| `make-payment` | 💳 Make monthly payment | loan-id, amount |
| `liquidate-loan` | ⚠️ Liquidate defaulted loan | loan-id |
| `emergency-withdraw` | 🆘 Cancel pending request | loan-id |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-loan` | 🔍 Get loan details | Loan data |
| `get-borrower-loans` | 👤 Get borrower's loans | List of loan IDs |
| `get-lender-loans` | 🏦 Get lender's loans | List of loan IDs |
| `calculate-monthly-payment` | 🧮 Calculate payment amount | Payment amount |
| `get-total-loans` | 📊 Get total loan count | Number |
| `is-payment-overdue` | ⏰ Check if payment overdue | Boolean |

## 🔧 Installation & Testing

1. **Clone the repository**
   ```bash
   git clone https://github.com/plaintainc/Decentralized-Mortgage-System.git
   cd Decentralized-Mortgage-System
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Run tests**
   ```bash
   npm test
   ```

4. **Check contract syntax**
   ```bash
   clarinet check
   ```

## 📊 Loan Lifecycle

```
📝 Created → 💰 Funded → 🔄 Active → ✅ Completed
                    ↓
               ⚠️ Defaulted (if overdue)
```

## 🛡️ Security Features

- ✅ Collateral requirement (must be >= loan amount)
- ✅ Payment validation and tracking
- ✅ Automatic liquidation for defaults
- ✅ Owner-only administrative functions
- ✅ Balance verification before transfers

## 📋 Loan Status Types

- `pending` - 🟡 Awaiting funding
- `active` - 🟢 Currently being repaid
- `completed` - ✅ Fully paid off
- `defaulted` - 🔴 Liquidated due to default
- `cancelled` - ❌ Cancelled by borrower

## 💡 Usage Examples

### Check Loan Status
```clarity
(contract-call? .decentralized-mortgage-system get-loan u1)
```

### View Payment History
```clarity
(contract-call? .decentralized-mortgage-system get-loan-payments u1)
```

### Calculate Monthly Payment
```clarity
(contract-call? .decentralized-mortgage-system calculate-monthly-payment 
  u1000000 u500 u8640)
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

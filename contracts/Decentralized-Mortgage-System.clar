(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-invalid-params (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-loan-not-active (err u106))
(define-constant err-loan-defaulted (err u107))
(define-constant err-payment-overdue (err u108))
(define-constant err-escrow-insufficient (err u109))
(define-constant err-escrow-overpayment (err u110))

(define-data-var next-loan-id uint u1)
(define-data-var total-loans uint u0)
(define-data-var total-volume uint u0)

(define-map loans
    uint
    {
        borrower: principal,
        lender: (optional principal),
        amount: uint,
        interest-rate: uint,
        term-blocks: uint,
        collateral-amount: uint,
        status: (string-ascii 20),
        created-at: uint,
        funded-at: (optional uint),
        monthly-payment: uint,
        payments-made: uint,
        last-payment-block: (optional uint),
    }
)

(define-map borrower-loans
    principal
    (list 50 uint)
)
(define-map lender-loans
    principal
    (list 50 uint)
)
(define-map loan-payments
    uint
    (list 100 {
        amount: uint,
        block: uint,
        type: (string-ascii 15),
    })
)

(define-map borrower-ratings
    principal
    {
        score: uint,
        total-loans: uint,
        completed-loans: uint,
        defaulted-loans: uint,
        total-payments: uint,
        on-time-payments: uint,
        last-updated: uint,
    }
)

;; Loan Interest Escrow System
(define-map loan-escrow
    uint ;; loan-id
    {
        balance: uint,
        total-deposited: uint,
        total-withdrawn: uint,
        auto-pay-enabled: bool,
        min-balance-threshold: uint,
        last-activity-block: uint,
    }
)

(define-map escrow-transactions
    uint ;; loan-id
    (list 200 {
        amount: uint,
        block: uint,
        transaction-type: (string-ascii 10), ;; "deposit" or "withdraw"
        remaining-balance: uint,
    })
)

(define-public (create-mortgage-request
        (amount uint)
        (interest-rate uint)
        (term-blocks uint)
        (collateral-amount uint)
    )
    (let ((loan-id (var-get next-loan-id)))
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (> interest-rate u0) err-invalid-params)
        (asserts! (> term-blocks u0) err-invalid-params)
        (asserts! (>= collateral-amount amount) err-invalid-params)
        (asserts! (>= (stx-get-balance tx-sender) collateral-amount)
            err-insufficient-funds
        )

        (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))

        (let ((monthly-payment (calculate-monthly-payment amount interest-rate term-blocks)))
            (map-set loans loan-id {
                borrower: tx-sender,
                lender: none,
                amount: amount,
                interest-rate: interest-rate,
                term-blocks: term-blocks,
                collateral-amount: collateral-amount,
                status: "pending",
                created-at: stacks-block-height,
                funded-at: none,
                monthly-payment: monthly-payment,
                payments-made: u0,
                last-payment-block: none,
            })

            (map-set borrower-loans tx-sender
                (unwrap!
                    (as-max-len?
                        (append
                            (default-to (list)
                                (map-get? borrower-loans tx-sender)
                            )
                            loan-id
                        )
                        u50
                    )
                    err-invalid-params
                ))

            (var-set next-loan-id (+ loan-id u1))
            (var-set total-loans (+ (var-get total-loans) u1))
            (ok loan-id)
        )
    )
)

(define-public (fund-mortgage (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq (get status loan) "pending") err-invalid-params)
        (asserts! (>= (stx-get-balance tx-sender) (get amount loan))
            err-insufficient-funds
        )

        (try! (stx-transfer? (get amount loan) tx-sender (get borrower loan)))

        (map-set loans loan-id
            (merge loan {
                lender: (some tx-sender),
                status: "active",
                funded-at: (some stacks-block-height),
            })
        )

        (map-set lender-loans tx-sender
            (unwrap!
                (as-max-len?
                    (append (default-to (list) (map-get? lender-loans tx-sender))
                        loan-id
                    )
                    u50
                )
                err-invalid-params
            ))

        (var-set total-volume (+ (var-get total-volume) (get amount loan)))
        (ok true)
    )
)

(define-public (make-payment
        (loan-id uint)
        (amount uint)
    )
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)
        (asserts! (is-eq (get status loan) "active") err-loan-not-active)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-funds)

        (let ((lender (unwrap! (get lender loan) err-not-found)))
            (try! (stx-transfer? amount tx-sender lender))

            (let ((new-payments (+ (get payments-made loan) u1)))
                (map-set loans loan-id
                    (merge loan {
                        payments-made: new-payments,
                        last-payment-block: (some stacks-block-height),
                        status: (if (>= new-payments (/ (get term-blocks loan) u30))
                            "completed"
                            "active"
                        ),
                    })
                )

                (let ((current-payments (default-to (list) (map-get? loan-payments loan-id))))
                    (map-set loan-payments loan-id
                        (unwrap!
                            (as-max-len?
                                (append current-payments {
                                    amount: amount,
                                    block: stacks-block-height,
                                    type: "payment",
                                })
                                u100
                            )
                            err-invalid-params
                        ))
                )

                (unwrap! (update-borrower-rating tx-sender true)
                    err-invalid-params
                )
                (ok true)
            )
        )
    )
)

(define-public (liquidate-loan (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-some (get lender loan)) err-not-found)
        (asserts!
            (or
                (is-eq tx-sender (unwrap-panic (get lender loan)))
                (is-eq tx-sender contract-owner)
            )
            err-unauthorized
        )

        (let ((blocks-since-funded (- stacks-block-height (unwrap! (get funded-at loan) err-not-found))))
            (asserts!
                (and
                    (is-eq (get status loan) "active")
                    (> blocks-since-funded (* u30 u144))
                    (is-none (get last-payment-block loan))
                )
                err-invalid-params
            )

            (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender
                (unwrap-panic (get lender loan))
            )))

            (map-set loans loan-id (merge loan { status: "defaulted" }))

            (unwrap! (update-borrower-rating (get borrower loan) false)
                err-invalid-params
            )

            (let ((current-payments (default-to (list) (map-get? loan-payments loan-id))))
                (map-set loan-payments loan-id
                    (unwrap!
                        (as-max-len?
                            (append current-payments {
                                amount: (get collateral-amount loan),
                                block: stacks-block-height,
                                type: "liquidation",
                            })
                            u100
                        )
                        err-invalid-params
                    ))
            )

            (ok true)
        )
    )
)

(define-public (update-loan-status
        (loan-id uint)
        (new-status (string-ascii 20))
    )
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)

        (map-set loans loan-id (merge loan { status: new-status }))
        (ok true)
    )
)

(define-public (emergency-withdraw (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)
        (asserts! (is-eq (get status loan) "pending") err-invalid-params)

        (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender (get borrower loan))))

        (map-set loans loan-id (merge loan { status: "cancelled" }))
        (ok true)
    )
)

;; Loan Interest Escrow System Functions

(define-public (deposit-to-escrow
        (loan-id uint)
        (amount uint)
    )
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)
        (asserts!
            (or 
                (is-eq (get status loan) "active")
                (is-eq (get status loan) "pending")
            )
            err-loan-not-active
        )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-funds)

        ;; Transfer funds to contract escrow
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

        ;; Update escrow balance
        (let ((current-escrow (default-to {
                    balance: u0,
                    total-deposited: u0,
                    total-withdrawn: u0,
                    auto-pay-enabled: false,
                    min-balance-threshold: u0,
                    last-activity-block: u0,
                }
                (map-get? loan-escrow loan-id)
            )))
            (let ((new-balance (+ (get balance current-escrow) amount)))
                (map-set loan-escrow loan-id
                    (merge current-escrow {
                        balance: new-balance,
                        total-deposited: (+ (get total-deposited current-escrow) amount),
                        last-activity-block: stacks-block-height,
                    })
                )

                ;; Record transaction
                (let ((current-transactions (default-to (list)
                        (map-get? escrow-transactions loan-id)
                    )))
                    (map-set escrow-transactions loan-id
                        (unwrap!
                            (as-max-len?
                                (append current-transactions {
                                    amount: amount,
                                    block: stacks-block-height,
                                    transaction-type: "deposit",
                                    remaining-balance: new-balance,
                                })
                                u200
                            )
                            err-invalid-params
                        )
                    )
                )

                (ok new-balance)
            )
        )
    )
)

(define-public (withdraw-from-escrow
        (loan-id uint)
        (amount uint)
    )
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)
        (let ((current-escrow (unwrap! (map-get? loan-escrow loan-id) err-not-found)))
            (asserts! (>= (get balance current-escrow) amount) err-escrow-insufficient)
            (asserts! (> amount u0) err-invalid-amount)

            ;; Transfer funds back to borrower
            (try! (as-contract (stx-transfer? amount tx-sender (get borrower loan))))

            ;; Update escrow balance
            (let ((new-balance (- (get balance current-escrow) amount)))
                (map-set loan-escrow loan-id
                    (merge current-escrow {
                        balance: new-balance,
                        total-withdrawn: (+ (get total-withdrawn current-escrow) amount),
                        last-activity-block: stacks-block-height,
                    })
                )

                ;; Record transaction
                (let ((current-transactions (default-to (list)
                        (map-get? escrow-transactions loan-id)
                    )))
                    (map-set escrow-transactions loan-id
                        (unwrap!
                            (as-max-len?
                                (append current-transactions {
                                    amount: amount,
                                    block: stacks-block-height,
                                    transaction-type: "withdraw",
                                    remaining-balance: new-balance,
                                })
                                u200
                            )
                            err-invalid-params
                        )
                    )
                )

                (ok new-balance)
            )
        )
    )
)

(define-public (enable-auto-pay
        (loan-id uint)
        (min-threshold uint)
    )
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)
        (asserts! (is-eq (get status loan) "active") err-loan-not-active)

        (let ((current-escrow (default-to {
                    balance: u0,
                    total-deposited: u0,
                    total-withdrawn: u0,
                    auto-pay-enabled: false,
                    min-balance-threshold: u0,
                    last-activity-block: u0,
                }
                (map-get? loan-escrow loan-id)
            )))
            (map-set loan-escrow loan-id
                (merge current-escrow {
                    auto-pay-enabled: true,
                    min-balance-threshold: min-threshold,
                    last-activity-block: stacks-block-height,
                })
            )
            (ok true)
        )
    )
)

(define-public (disable-auto-pay (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq tx-sender (get borrower loan)) err-unauthorized)

        (let ((current-escrow (unwrap! (map-get? loan-escrow loan-id) err-not-found)))
            (map-set loan-escrow loan-id
                (merge current-escrow {
                    auto-pay-enabled: false,
                    min-balance-threshold: u0,
                    last-activity-block: stacks-block-height,
                })
            )
            (ok true)
        )
    )
)

(define-public (make-escrow-payment (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) err-not-found)))
        (asserts! (is-eq (get status loan) "active") err-loan-not-active)
        (let ((lender (unwrap! (get lender loan) err-not-found))
              (escrow (unwrap! (map-get? loan-escrow loan-id) err-not-found))
              (payment-amount (get monthly-payment loan)))
            (asserts! (get auto-pay-enabled escrow) err-invalid-params)
            (asserts! (>= (get balance escrow) payment-amount) err-escrow-insufficient)

            ;; Transfer payment from escrow to lender
            (try! (as-contract (stx-transfer? payment-amount tx-sender lender)))

            ;; Update escrow balance
            (let ((new-balance (- (get balance escrow) payment-amount)))
                (map-set loan-escrow loan-id
                    (merge escrow {
                        balance: new-balance,
                        total-withdrawn: (+ (get total-withdrawn escrow) payment-amount),
                        last-activity-block: stacks-block-height,
                    })
                )

                ;; Update loan payment status
                (let ((new-payments (+ (get payments-made loan) u1)))
                    (map-set loans loan-id
                        (merge loan {
                            payments-made: new-payments,
                            last-payment-block: (some stacks-block-height),
                            status: (if (>= new-payments (/ (get term-blocks loan) u30))
                                "completed"
                                "active"
                            ),
                        })
                    )

                    ;; Record payment transaction
                    (let ((current-payments (default-to (list) (map-get? loan-payments loan-id))))
                        (map-set loan-payments loan-id
                            (unwrap!
                                (as-max-len?
                                    (append current-payments {
                                        amount: payment-amount,
                                        block: stacks-block-height,
                                        type: "escrow-payment",
                                    })
                                    u100
                                )
                                err-invalid-params
                            ))
                    )

                    ;; Record escrow transaction
                    (let ((current-escrow-transactions (default-to (list)
                            (map-get? escrow-transactions loan-id)
                        )))
                        (map-set escrow-transactions loan-id
                            (unwrap!
                                (as-max-len?
                                    (append current-escrow-transactions {
                                        amount: payment-amount,
                                        block: stacks-block-height,
                                        transaction-type: "withdraw",
                                        remaining-balance: new-balance,
                                    })
                                    u200
                                )
                                err-invalid-params
                            )
                        )
                    )

                    ;; Update borrower rating
                    (unwrap! (update-borrower-rating (get borrower loan) true)
                        err-invalid-params
                    )
                    (ok new-balance)
                )
            )
        )
    )
)

(define-read-only (get-loan (loan-id uint))
    (map-get? loans loan-id)
)

(define-read-only (get-borrower-loans (borrower principal))
    (map-get? borrower-loans borrower)
)

(define-read-only (get-lender-loans (lender principal))
    (map-get? lender-loans lender)
)

(define-read-only (get-loan-payments (loan-id uint))
    (map-get? loan-payments loan-id)
)

(define-read-only (calculate-monthly-payment
        (principal-amount uint)
        (annual-rate uint)
        (term-blocks uint)
    )
    (let (
            (monthly-rate (/ annual-rate u1200))
            (num-payments (/ term-blocks u30))
        )
        (if (is-eq monthly-rate u0)
            (/ principal-amount num-payments)
            (let ((factor (pow (+ u100 monthly-rate) num-payments)))
                (/ (* principal-amount (* monthly-rate factor)) (- factor u100))
            )
        )
    )
)

(define-read-only (get-loan-status (loan-id uint))
    (match (map-get? loans loan-id)
        loan (get status loan)
        "not-found"
    )
)

(define-read-only (is-payment-overdue (loan-id uint))
    (match (map-get? loans loan-id)
        loan (match (get last-payment-block loan)
            last-payment (> (- stacks-block-height last-payment) (* u30 u144))
            (> (- stacks-block-height (unwrap-panic (get funded-at loan)))
                (* u30 u144)
            )
        )
        false
    )
)

(define-read-only (get-total-loans)
    (var-get total-loans)
)

(define-read-only (get-total-volume)
    (var-get total-volume)
)

(define-read-only (get-next-loan-id)
    (var-get next-loan-id)
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (calculate-remaining-balance (loan-id uint))
    (match (map-get? loans loan-id)
        loan (let (
                (total-payments-expected (/ (get term-blocks loan) u30))
                (payments-made (get payments-made loan))
            )
            (if (>= payments-made total-payments-expected)
                u0
                (* (get monthly-payment loan)
                    (- total-payments-expected payments-made)
                )
            )
        )
        u0
    )
)

(define-private (update-borrower-rating
        (borrower principal)
        (is-positive bool)
    )
    (let ((current-rating (default-to {
            score: u500,
            total-loans: u0,
            completed-loans: u0,
            defaulted-loans: u0,
            total-payments: u0,
            on-time-payments: u0,
            last-updated: u0,
        }
            (map-get? borrower-ratings borrower)
        )))
        (let ((new-score (calculate-new-score current-rating is-positive)))
            (map-set borrower-ratings borrower
                (merge current-rating {
                    score: new-score,
                    total-payments: (+ (get total-payments current-rating) u1),
                    on-time-payments: (+ (get on-time-payments current-rating)
                        (if is-positive
                            u1
                            u0
                        )),
                    completed-loans: (+ (get completed-loans current-rating)
                        (if (and is-positive (> (get total-payments current-rating) u0))
                            u1
                            u0
                        )),
                    defaulted-loans: (+ (get defaulted-loans current-rating)
                        (if (not is-positive)
                            u1
                            u0
                        )),
                    last-updated: stacks-block-height,
                })
            )
            (ok true)
        )
    )
)

(define-private (calculate-new-score
        (rating {
            score: uint,
            total-loans: uint,
            completed-loans: uint,
            defaulted-loans: uint,
            total-payments: uint,
            on-time-payments: uint,
            last-updated: uint,
        })
        (is-positive bool)
    )
    (let (
            (current-score (get score rating))
            (payment-ratio (if (is-eq (get total-payments rating) u0)
                u100
                (/ (* (get on-time-payments rating) u100)
                    (get total-payments rating)
                )
            ))
            (default-ratio (if (is-eq (get total-loans rating) u0)
                u0
                (/ (* (get defaulted-loans rating) u100) (get total-loans rating))
            ))
        )
        (if is-positive
            (if (> (+ current-score u5) u1000)
                u1000
                (+ current-score u5)
            )
            (if (< (- current-score u50) u100)
                u100
                (- current-score u50)
            )
        )
    )
)

(define-read-only (get-borrower-rating (borrower principal))
    (map-get? borrower-ratings borrower)
)

(define-read-only (get-borrower-score (borrower principal))
    (match (map-get? borrower-ratings borrower)
        rating (get score rating)
        u500
    )
)

(define-read-only (is-borrower-high-risk (borrower principal))
    (< (get-borrower-score borrower) u300)
)

;; Escrow System Read-Only Functions

(define-read-only (get-escrow-balance (loan-id uint))
    (match (map-get? loan-escrow loan-id)
        escrow (get balance escrow)
        u0
    )
)

(define-read-only (get-escrow-details (loan-id uint))
    (map-get? loan-escrow loan-id)
)

(define-read-only (get-escrow-transactions (loan-id uint))
    (map-get? escrow-transactions loan-id)
)

(define-read-only (is-auto-pay-enabled (loan-id uint))
    (match (map-get? loan-escrow loan-id)
        escrow (get auto-pay-enabled escrow)
        false
    )
)

(define-read-only (can-make-escrow-payment (loan-id uint))
    (match (map-get? loans loan-id)
        loan (match (map-get? loan-escrow loan-id)
            escrow (and
                (is-eq (get status loan) "active")
                (get auto-pay-enabled escrow)
                (>= (get balance escrow) (get monthly-payment loan))
            )
            false
        )
        false
    )
)

(define-read-only (calculate-escrow-coverage (loan-id uint))
    (match (map-get? loans loan-id)
        loan (match (map-get? loan-escrow loan-id)
            escrow (let ((monthly-payment (get monthly-payment loan)))
                (if (is-eq monthly-payment u0)
                    u0
                    (/ (get balance escrow) monthly-payment)
                )
            )
            u0
        )
        u0
    )
)

(define-read-only (get-escrow-activity-summary (loan-id uint))
    (match (map-get? loan-escrow loan-id)
        escrow (some {
            current-balance: (get balance escrow),
            total-deposited: (get total-deposited escrow),
            total-withdrawn: (get total-withdrawn escrow),
            net-position: (- (get total-deposited escrow) (get total-withdrawn escrow)),
            auto-pay-status: (get auto-pay-enabled escrow),
            coverage-months: (match (map-get? loans loan-id)
                loan (let ((monthly-payment (get monthly-payment loan)))
                    (if (is-eq monthly-payment u0)
                        u0
                        (/ (get balance escrow) monthly-payment)
                    )
                )
                u0
            ),
            last-activity: (get last-activity-block escrow),
        })
        none
    )
)

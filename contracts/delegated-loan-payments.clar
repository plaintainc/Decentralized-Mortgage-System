(define-constant err-not-authorized u100)
(define-constant err-insufficient-allowance u101)
(define-constant err-zero-amount u102)

(define-data-var last-payment-id uint u0)

(define-map authorizations
  {borrower: principal, loan: principal, loan-id: uint, delegate: principal}
  {allowance: uint}
)

(define-map payments
  uint
  {loan: principal, loan-id: uint, borrower: principal, payer: principal, amount: uint}
)

(define-read-only (get-allowance (borrower principal) (loan principal) (loan-id uint) (delegate principal))
  (let ((auth (map-get? authorizations {borrower: borrower, loan: loan, loan-id: loan-id, delegate: delegate})))
    (if (is-some auth) (get allowance (unwrap-panic auth)) u0)
  )
)

(define-read-only (get-payment (payment-id uint))
  (map-get? payments payment-id)
)

(define-public (authorize-delegate (loan principal) (loan-id uint) (delegate principal) (allowance uint))
  (begin
    (map-set authorizations {borrower: tx-sender, loan: loan, loan-id: loan-id, delegate: delegate} {allowance: allowance})
    (ok true)
  )
)

(define-public (revoke-delegate (loan principal) (loan-id uint) (delegate principal))
  (let ((key {borrower: tx-sender, loan: loan, loan-id: loan-id, delegate: delegate}))
    (map-delete authorizations key)
    (ok true)
  )
)

(define-public (increase-allowance (loan principal) (loan-id uint) (delegate principal) (delta uint))
  (let (
    (key {borrower: tx-sender, loan: loan, loan-id: loan-id, delegate: delegate})
    (current (map-get? authorizations key))
    (current-allowance (if (is-some current) (get allowance (unwrap-panic current)) u0))
    (new-allowance (+ current-allowance delta))
  )
    (map-set authorizations key {allowance: new-allowance})
    (ok true)
  )
)

(define-public (decrease-allowance (loan principal) (loan-id uint) (delegate principal) (delta uint))
  (let (
    (key {borrower: tx-sender, loan: loan, loan-id: loan-id, delegate: delegate})
    (current (map-get? authorizations key))
    (current-allowance (if (is-some current) (get allowance (unwrap-panic current)) u0))
    (new-allowance (if (>= current-allowance delta) (- current-allowance delta) u0))
  )
    (if (is-eq new-allowance u0)
      (map-delete authorizations key)
      (map-set authorizations key {allowance: new-allowance}))
    (ok true)
  )
)

(define-public (pay-on-behalf-stx (loan principal) (loan-id uint) (borrower principal) (amount uint))
  (let (
    (key {borrower: borrower, loan: loan, loan-id: loan-id, delegate: tx-sender})
    (auth (map-get? authorizations key))
  )
    (if (is-eq amount u0)
      (err err-zero-amount)
      (if (is-none auth)
        (err err-not-authorized)
        (let ((allowance (get allowance (unwrap-panic auth))))
          (if (>= allowance amount)
            (begin
              (try! (stx-transfer? amount tx-sender loan))
              (let ((new-allowance (- allowance amount)))
                (if (is-eq new-allowance u0)
                  (map-delete authorizations key)
                  (map-set authorizations key {allowance: new-allowance}))
                (var-set last-payment-id (+ (var-get last-payment-id) u1))
                (let ((pid (var-get last-payment-id)))
                  (map-set payments pid {loan: loan, loan-id: loan-id, borrower: borrower, payer: tx-sender, amount: amount})
                  (ok pid))))
            (err err-insufficient-allowance))))))
)

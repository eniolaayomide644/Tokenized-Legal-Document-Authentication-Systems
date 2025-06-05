;; Contract Execution Contract
;; Executes legal contracts with multi-party signatures

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_ALREADY_SIGNED (err u302))
(define-constant ERR_ALREADY_EXECUTED (err u303))
(define-constant ERR_INSUFFICIENT_SIGNATURES (err u304))

;; Data structures
(define-map contracts
  { contract-id: uint }
  {
    contract-hash: (buff 32),
    parties: (list 10 principal),
    required-signatures: uint,
    created-by: principal,
    creation-time: uint,
    executed: bool,
    execution-time: uint
  }
)

(define-map contract-signatures
  { contract-id: uint, signer: principal }
  {
    signed: bool,
    signature-time: uint,
    signature-hash: (buff 32)
  }
)

(define-data-var next-contract-id uint u1)

;; Create a new contract
(define-public (create-contract
  (contract-hash (buff 32))
  (parties (list 10 principal))
  (required-signatures uint))
  (let ((contract-id (var-get next-contract-id)))
    (map-set contracts
      { contract-id: contract-id }
      {
        contract-hash: contract-hash,
        parties: parties,
        required-signatures: required-signatures,
        created-by: tx-sender,
        creation-time: block-height,
        executed: false,
        execution-time: u0
      }
    )
    (var-set next-contract-id (+ contract-id u1))
    (ok contract-id)
  )
)

;; Sign a contract
(define-public (sign-contract
  (contract-id uint)
  (signature-hash (buff 32)))
  (begin
    ;; Check if contract exists
    (asserts! (is-some (map-get? contracts { contract-id: contract-id })) ERR_NOT_FOUND)
    ;; Check if already signed
    (asserts! (is-none (map-get? contract-signatures { contract-id: contract-id, signer: tx-sender })) ERR_ALREADY_SIGNED)
    ;; Check if sender is a party to the contract
    (asserts! (is-contract-party contract-id tx-sender) ERR_UNAUTHORIZED)
    ;; Record signature
    (map-set contract-signatures
      { contract-id: contract-id, signer: tx-sender }
      {
        signed: true,
        signature-time: block-height,
        signature-hash: signature-hash
      }
    )
    ;; Check if contract can be executed
    (try! (attempt-execution contract-id))
    (ok true)
  )
)

;; Attempt to execute contract if enough signatures
(define-private (attempt-execution (contract-id uint))
  (match (map-get? contracts { contract-id: contract-id })
    contract-data
    (let ((signature-count (count-signatures contract-id)))
      (if (and
            (>= signature-count (get required-signatures contract-data))
            (not (get executed contract-data)))
        (begin
          (map-set contracts
            { contract-id: contract-id }
            (merge contract-data {
              executed: true,
              execution-time: block-height
            })
          )
          (ok true)
        )
        (ok false)
      )
    )
    ERR_NOT_FOUND
  )
)

;; Count signatures for a contract
(define-private (count-signatures (contract-id uint))
  ;; Simplified signature counting - in practice would iterate through parties
  u0
)

;; Check if principal is party to contract
(define-read-only (is-contract-party (contract-id uint) (party principal))
  (match (map-get? contracts { contract-id: contract-id })
    contract-data
    (is-some (index-of (get parties contract-data) party))
    false
  )
)

;; Get contract details
(define-read-only (get-contract (contract-id uint))
  (map-get? contracts { contract-id: contract-id })
)

;; Get signature status
(define-read-only (get-signature (contract-id uint) (signer principal))
  (map-get? contract-signatures { contract-id: contract-id, signer: signer })
)

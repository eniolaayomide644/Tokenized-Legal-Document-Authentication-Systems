;; Dispute Resolution Contract
;; Resolves legal disputes through arbitration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_NOT_FOUND (err u501))
(define-constant ERR_DISPUTE_CLOSED (err u502))
(define-constant ERR_INVALID_STATUS (err u503))
(define-constant ERR_ALREADY_VOTED (err u504))

;; Dispute status constants
(define-constant STATUS_OPEN u1)
(define-constant STATUS_IN_ARBITRATION u2)
(define-constant STATUS_RESOLVED u3)
(define-constant STATUS_CLOSED u4)

;; Data structures
(define-map disputes
  { dispute-id: uint }
  {
    plaintiff: principal,
    defendant: principal,
    case-description: (string-ascii 1000),
    evidence-ids: (list 10 uint),
    arbitrators: (list 5 principal),
    status: uint,
    creation-time: uint,
    resolution-time: uint,
    resolution: (string-ascii 1000),
    winning-party: (optional principal)
  }
)

(define-map arbitrator-votes
  { dispute-id: uint, arbitrator: principal }
  {
    vote: (string-ascii 500),
    voted-for: principal,
    vote-time: uint
  }
)

(define-map authorized-arbitrators
  { arbitrator: principal }
  {
    authorized: bool,
    specialization: (string-ascii 100),
    authorization-date: uint
  }
)

(define-data-var next-dispute-id uint u1)

;; Authorize an arbitrator
(define-public (authorize-arbitrator
  (arbitrator principal)
  (specialization (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-arbitrators
      { arbitrator: arbitrator }
      {
        authorized: true,
        specialization: specialization,
        authorization-date: block-height
      }
    )
    (ok true)
  )
)

;; File a dispute
(define-public (file-dispute
  (defendant principal)
  (case-description (string-ascii 1000))
  (evidence-ids (list 10 uint))
  (arbitrators (list 5 principal)))
  (let ((dispute-id (var-get next-dispute-id)))
    ;; Verify all arbitrators are authorized
    (asserts! (all-arbitrators-authorized arbitrators) ERR_UNAUTHORIZED)
    (map-set disputes
      { dispute-id: dispute-id }
      {
        plaintiff: tx-sender,
        defendant: defendant,
        case-description: case-description,
        evidence-ids: evidence-ids,
        arbitrators: arbitrators,
        status: STATUS_OPEN,
        creation-time: block-height,
        resolution-time: u0,
        resolution: "",
        winning-party: none
      }
    )
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

;; Start arbitration
(define-public (start-arbitration (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-data
    (begin
      ;; Only authorized arbitrators can start arbitration
      (asserts! (is-authorized-arbitrator tx-sender) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status dispute-data) STATUS_OPEN) ERR_INVALID_STATUS)
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute-data { status: STATUS_IN_ARBITRATION })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Submit arbitrator vote
(define-public (submit-vote
  (dispute-id uint)
  (vote (string-ascii 500))
  (voted-for principal))
  (begin
    ;; Check if arbitrator is authorized and assigned to this dispute
    (asserts! (is-dispute-arbitrator dispute-id tx-sender) ERR_UNAUTHORIZED)
    ;; Check if already voted
    (asserts! (is-none (map-get? arbitrator-votes { dispute-id: dispute-id, arbitrator: tx-sender })) ERR_ALREADY_VOTED)
    ;; Check dispute status
    (asserts! (is-dispute-in-arbitration dispute-id) ERR_INVALID_STATUS)
    ;; Record vote
    (map-set arbitrator-votes
      { dispute-id: dispute-id, arbitrator: tx-sender }
      {
        vote: vote,
        voted-for: voted-for,
        vote-time: block-height
      }
    )
    ;; Check if enough votes to resolve
    (try! (attempt-resolution dispute-id))
    (ok true)
  )
)

;; Attempt to resolve dispute based on votes
(define-private (attempt-resolution (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-data
    (let ((vote-count (count-votes dispute-id)))
      ;; Simplified resolution logic - in practice would count actual votes
      (if (>= vote-count u3) ;; Majority of 5 arbitrators
        (begin
          (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute-data {
              status: STATUS_RESOLVED,
              resolution-time: block-height,
              resolution: "Dispute resolved by arbitration",
              winning-party: (some (get plaintiff dispute-data)) ;; Simplified
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

;; Helper functions
(define-private (all-arbitrators-authorized (arbitrators (list 5 principal)))
  ;; Simplified check - would iterate through list in practice
  true
)

(define-private (count-votes (dispute-id uint))
  ;; Simplified vote counting
  u3
)

(define-read-only (is-authorized-arbitrator (arbitrator principal))
  (match (map-get? authorized-arbitrators { arbitrator: arbitrator })
    arbitrator-info (get authorized arbitrator-info)
    false
  )
)

(define-read-only (is-dispute-arbitrator (dispute-id uint) (arbitrator principal))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-data
    (is-some (index-of (get arbitrators dispute-data) arbitrator))
    false
  )
)

(define-read-only (is-dispute-in-arbitration (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-data
    (is-eq (get status dispute-data) STATUS_IN_ARBITRATION)
    false
  )
)

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

;; Get arbitrator vote
(define-read-only (get-arbitrator-vote (dispute-id uint) (arbitrator principal))
  (map-get? arbitrator-votes { dispute-id: dispute-id, arbitrator: arbitrator })
)

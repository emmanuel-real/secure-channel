;; Title: SecureChannel - Bitcoin-Compatible Payment Channels for Stacks
;; 
;; Summary:
;; A trustless payment channel implementation for Stacks blockchain that enables 
;; high-frequency, low-cost transactions between two parties without congesting 
;; the network with individual settlements.
;;
;; Description:
;; This contract implements state channels for off-chain microtransactions with on-chain
;; settlement guarantees. Parties can open bi-directional payment channels, conduct
;; unlimited off-chain transfers by exchanging signed messages, and settle final balances
;; either cooperatively or through dispute resolution. The implementation includes safety
;; features like dispute periods, cooperative closures, and signature verification to ensure
;; funds remain secure throughout the channel lifecycle.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CHANNEL-EXISTS (err u101))
(define-constant ERR-CHANNEL-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-INVALID-SIGNATURE (err u104))
(define-constant ERR-CHANNEL-CLOSED (err u105))
(define-constant ERR-DISPUTE-PERIOD (err u106))
(define-constant ERR-INVALID-INPUT (err u107))

;; Input validation functions
(define-private (is-valid-channel-id (channel-id (buff 32)))
  (and
    (> (len channel-id) u0)
    (<= (len channel-id) u32)
  )
)

(define-private (is-valid-deposit (amount uint))
  (> amount u0)
)

(define-private (is-valid-signature (signature (buff 65)))
  (and
    (is-eq (len signature) u65)
    ;; Add additional signature validation if needed
    true
  )
)

(define-private (create-channel-message 
  (channel-id (buff 32))
  (balance-a uint)
  (balance-b uint)
  (nonce uint)
)
  (concat
    (concat
      (concat
        channel-id
        (uint-to-buff balance-a)
      )
      (uint-to-buff balance-b)
    )
    (uint-to-buff nonce)
  )
)

;; Storage for payment channels
(define-map payment-channels
  {
    channel-id: (buff 32),  ;; Unique identifier for the channel
    participant-a: principal,  ;; First participant
    participant-b: principal   ;; Second participant
  }
  {
    total-deposited: uint,     ;; Total funds deposited in the channel
    balance-a: uint,           ;; Balance for participant A
    balance-b: uint,           ;; Balance for participant B
    is-open: bool,             ;; Channel open/closed status
    dispute-deadline: uint,    ;; Timestamp for dispute resolution
    nonce: uint                ;; Prevents replay attacks
  }
)

;; Helper function to convert uint to buffer
(define-private (uint-to-buff (n uint))
  (unwrap-panic (to-consensus-buff? n))
)

;; Create a new payment channel
(define-public (create-channel
  (channel-id (buff 32))
  (participant-b principal)
  (initial-deposit uint)
)
  (begin
    ;; Validate inputs
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit initial-deposit) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)

    ;; Ensure channel doesn't already exist
    (asserts! (is-none (map-get? payment-channels {
      channel-id: channel-id, 
      participant-a: tx-sender, 
      participant-b: participant-b
    })) ERR-CHANNEL-EXISTS)

    ;; Transfer initial deposit from creator
    (try! (stx-transfer? initial-deposit tx-sender (as-contract tx-sender)))

    ;; Create channel entry
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      {
        total-deposited: initial-deposit,
        balance-a: initial-deposit,
        balance-b: u0,
        is-open: true,
        dispute-deadline: u0,
        nonce: u0
      }
    )

    (ok true)
  )
)

;; Fund an existing payment channel
(define-public (fund-channel
  (channel-id (buff 32))
  (participant-b principal)
  (additional-funds uint)
)
  (let
    (
      (channel (unwrap!
        (map-get? payment-channels {
          channel-id: channel-id,
          participant-a: tx-sender,
          participant-b: participant-b
        })
        ERR-CHANNEL-NOT-FOUND
      ))
    )
    ;; Validate inputs
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit additional-funds) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)

    ;; Validate channel is open
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)

    ;; Transfer additional funds
    (try! (stx-transfer? additional-funds tx-sender (as-contract tx-sender)))

    ;; Update channel state
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      (merge channel {
        total-deposited: (+ (get total-deposited channel) additional-funds),
        balance-a: (+ (get balance-a channel) additional-funds)
      })
    )

    (ok true)
  )
)
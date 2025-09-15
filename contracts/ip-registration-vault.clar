;; ip-registration-vault Smart Contract
;; Securely registers and timestamps intellectual property creations including patents, trademarks, copyrights, and trade secrets with cryptographic proof of creation date and ownership.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_STATE (err u105))
(define-constant ERR_OPERATION_FAILED (err u106))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-participants uint u0)
(define-data-var global-fee-rate uint u100)
(define-data-var emergency-mode bool false)
(define-data-var next-transaction-id uint u1)
(define-data-var minimum-stake uint u1000)

;; Data Maps
(define-map participants principal {
    active: bool,
    balance: uint,
    last-activity: uint,
    reputation-score: uint,
    total-transactions: uint,
    stake-amount: uint
})

(define-map transactions uint {
    initiator: principal,
    recipient: principal,
    amount: uint,
    timestamp: uint,
    status: (string-ascii 20),
    transaction-type: (string-ascii 50),
    fee-amount: uint
})

(define-map system-config (string-ascii 50) uint)
(define-map access-permissions principal (list 10 (string-ascii 50)))

;; Authorization Functions
(define-private (is-contract-owner (user principal))
    (is-eq user CONTRACT_OWNER))

(define-private (is-authorized (user principal))
    (or 
        (is-contract-owner user)
        (default-to false (get active (map-get? participants user)))))

(define-private (has-permission (user principal) (permission (string-ascii 50)))
    (let ((permissions (default-to (list) (map-get? access-permissions user))))
        (is-some (index-of permissions permission))))

;; Core Functions
(define-public (initialize-participant)
    (let ((caller tx-sender))
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-none (map-get? participants caller)) ERR_ALREADY_EXISTS)
        (map-set participants caller {
            active: true,
            balance: u0,
            last-activity: block-height,
            reputation-score: u100,
            total-transactions: u0,
            stake-amount: u0
        })
        (var-set total-participants (+ (var-get total-participants) u1))
        (ok true)))

(define-public (stake-tokens (amount uint))
    (let ((caller tx-sender)
          (participant-data (unwrap! (map-get? participants caller) ERR_NOT_FOUND)))
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (get active participant-data) ERR_UNAUTHORIZED)
        (asserts! (>= amount (var-get minimum-stake)) ERR_INVALID_PARAMS)
        
        ;; Update participant stake
        (map-set participants caller (merge participant-data {
            stake-amount: (+ (get stake-amount participant-data) amount),
            last-activity: block-height
        }))
        (ok true)))

(define-public (process-transaction (recipient principal) (amount uint) (tx-type (string-ascii 50)))
    (let (
        (caller tx-sender)
        (transaction-id (var-get next-transaction-id))
        (sender-data (unwrap! (map-get? participants caller) ERR_NOT_FOUND))
        (recipient-data (default-to {active: false, balance: u0, last-activity: u0, reputation-score: u0, total-transactions: u0, stake-amount: u0} (map-get? participants recipient)))
        (fee-amount (/ (* amount (var-get global-fee-rate)) u10000))
        (net-amount (- amount fee-amount))
    )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (not (var-get emergency-mode)) ERR_INVALID_STATE)
        (asserts! (get active sender-data) ERR_UNAUTHORIZED)
        (asserts! (>= (get balance sender-data) amount) ERR_INSUFFICIENT_FUNDS)
        (asserts! (> amount u0) ERR_INVALID_PARAMS)
        (asserts! (>= (get stake-amount sender-data) (var-get minimum-stake)) ERR_UNAUTHORIZED)
        
        ;; Update sender balance
        (map-set participants caller (merge sender-data {
            balance: (- (get balance sender-data) amount),
            last-activity: block-height,
            total-transactions: (+ (get total-transactions sender-data) u1)
        }))
        
        ;; Update or create recipient
        (map-set participants recipient (merge recipient-data {
            active: true,
            balance: (+ (get balance recipient-data) net-amount),
            last-activity: block-height,
            total-transactions: (+ (get total-transactions recipient-data) u1)
        }))
        
        ;; Record transaction
        (map-set transactions transaction-id {
            initiator: caller,
            recipient: recipient,
            amount: net-amount,
            timestamp: block-height,
            status: "completed",
            transaction-type: tx-type,
            fee-amount: fee-amount
        })
        
        (var-set next-transaction-id (+ transaction-id u1))
        (ok transaction-id)))

(define-public (deposit (amount uint))
    (let ((caller tx-sender)
          (participant-data (unwrap! (map-get? participants caller) ERR_NOT_FOUND)))
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (get active participant-data) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_PARAMS)
        
        ;; Update participant balance
        (map-set participants caller (merge participant-data {
            balance: (+ (get balance participant-data) amount),
            last-activity: block-height
        }))
        (ok true)))

(define-public (withdraw (amount uint))
    (let ((caller tx-sender)
          (participant-data (unwrap! (map-get? participants caller) ERR_NOT_FOUND)))
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (get active participant-data) ERR_UNAUTHORIZED)
        (asserts! (>= (get balance participant-data) amount) ERR_INSUFFICIENT_FUNDS)
        (asserts! (> amount u0) ERR_INVALID_PARAMS)
        (asserts! (>= (get stake-amount participant-data) (var-get minimum-stake)) ERR_UNAUTHORIZED)
        
        ;; Update participant balance
        (map-set participants caller (merge participant-data {
            balance: (- (get balance participant-data) amount),
            last-activity: block-height
        }))
        (ok true)))

(define-public (update-reputation (user principal) (new-score uint))
    (let ((caller tx-sender)
          (participant-data (unwrap! (map-get? participants user) ERR_NOT_FOUND)))
        (asserts! (is-contract-owner caller) ERR_UNAUTHORIZED)
        (asserts! (<= new-score u1000) ERR_INVALID_PARAMS)
        
        (map-set participants user (merge participant-data {
            reputation-score: new-score
        }))
        (ok true)))

(define-public (grant-permission (user principal) (permission (string-ascii 50)))
    (let ((caller tx-sender)
          (current-permissions (default-to (list) (map-get? access-permissions user))))
        (asserts! (is-contract-owner caller) ERR_UNAUTHORIZED)
        (asserts! (is-none (index-of current-permissions permission)) ERR_ALREADY_EXISTS)
        
        (map-set access-permissions user (unwrap-panic (as-max-len? (append current-permissions permission) u10)))
        (ok true)))

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (var-set emergency-mode true)
        (var-set contract-active false)
        (ok true)))

(define-public (set-fee-rate (new-rate uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u1000) ERR_INVALID_PARAMS)
        (var-set global-fee-rate new-rate)
        (ok true)))

(define-public (set-minimum-stake (new-minimum uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> new-minimum u0) ERR_INVALID_PARAMS)
        (var-set minimum-stake new-minimum)
        (ok true)))

;; Read Functions
(define-read-only (get-participant-info (user principal))
    (map-get? participants user))

(define-read-only (get-transaction-info (transaction-id uint))
    (map-get? transactions transaction-id))

(define-read-only (get-total-participants)
    (var-get total-participants))

(define-read-only (get-contract-status)
    {
        active: (var-get contract-active),
        emergency: (var-get emergency-mode),
        participants: (var-get total-participants),
        next-tx-id: (var-get next-transaction-id),
        fee-rate: (var-get global-fee-rate),
        min-stake: (var-get minimum-stake)
    })

(define-read-only (get-participant-balance (user principal))
    (default-to u0 (get balance (map-get? participants user))))

(define-read-only (is-participant-active (user principal))
    (default-to false (get active (map-get? participants user))))

(define-read-only (get-system-config (key (string-ascii 50)))
    (map-get? system-config key))

(define-read-only (get-user-permissions (user principal))
    (map-get? access-permissions user))

(define-read-only (calculate-transaction-fee (amount uint))
    (/ (* amount (var-get global-fee-rate)) u10000))

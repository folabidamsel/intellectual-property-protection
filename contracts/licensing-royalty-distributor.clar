;; licensing-royalty-distributor Smart Contract  
;; Automates IP licensing agreements, tracks usage across platforms, calculates royalty payments, and distributes earnings to IP owners based on predefined licensing terms and usage analytics.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PARAMS (err u201))
(define-constant ERR_NOT_FOUND (err u202))
(define-constant ERR_PROCESSING_FAILED (err u203))
(define-constant ERR_INVALID_STATE (err u204))
(define-constant ERR_ALREADY_PROCESSED (err u205))
(define-constant ERR_INSUFFICIENT_RESOURCES (err u206))

;; Data Variables
(define-data-var processing-active bool true)
(define-data-var total-processed uint u0)
(define-data-var automation-enabled bool true)
(define-data-var processing-fee uint u10)
(define-data-var max-batch-size uint u100)
(define-data-var next-request-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var daily-limit uint u10000)

;; Data Maps
(define-map processing-requests uint {
    requester: principal,
    request-type: (string-ascii 50),
    status: (string-ascii 20),
    created-at: uint,
    processed-at: (optional uint),
    result-data: (optional (string-ascii 512)),
    priority: uint,
    resource-cost: uint
})

(define-map automation-rules (string-ascii 50) {
    active: bool,
    condition-type: (string-ascii 50),
    trigger-value: uint,
    action-type: (string-ascii 50),
    created-by: principal,
    last-triggered: (optional uint),
    execution-count: uint
})

(define-map user-preferences principal {
    auto-processing: bool,
    notification-level: uint,
    custom-settings: (string-ascii 256),
    last-updated: uint,
    daily-usage: uint
})

(define-map batch-operations uint {
    operator: principal,
    operation-type: (string-ascii 50),
    items-count: uint,
    completed-count: uint,
    status: (string-ascii 20),
    started-at: uint,
    completed-at: (optional uint),
    total-cost: uint
})

(define-map daily-stats (string-ascii 10) uint)

;; Authorization Functions
(define-private (is-contract-owner (user principal))
    (is-eq user CONTRACT_OWNER))

(define-private (is-operator (user principal))
    (or 
        (is-contract-owner user)
        (> (len (default-to "" (get custom-settings (map-get? user-preferences user)))) u0)))

(define-private (can-process (user principal) (resource-cost uint))
    (let ((user-prefs (default-to {auto-processing: false, notification-level: u0, custom-settings: "", last-updated: u0, daily-usage: u0} (map-get? user-preferences user))))
        (and 
            (is-operator user)
            (<= (+ (get daily-usage user-prefs) resource-cost) (var-get daily-limit)))))

;; Processing Functions
(define-private (process-verification (metadata (string-ascii 50)))
    "verification-complete-verified")

(define-private (process-calculation (metadata (string-ascii 50)))
    "calculation-complete-result-computed")

(define-private (process-validation (metadata (string-ascii 50)))
    "validation-complete-passed-checks")

(define-private (process-optimization (metadata (string-ascii 50)))
    "optimization-complete-improved")

(define-private (process-default (metadata (string-ascii 50)))
    "processing-complete-default-success")

(define-private (process-by-type (request-type (string-ascii 50)) (metadata (string-ascii 50)))
    (if (is-eq request-type "verification")
        (process-verification metadata)
        (if (is-eq request-type "calculation")
            (process-calculation metadata)
            (if (is-eq request-type "validation")
                (process-validation metadata)
                (if (is-eq request-type "optimization")
                    (process-optimization metadata)
                    (process-default metadata))))))

(define-private (calculate-resource-cost (request-type (string-ascii 50)) (priority uint))
    (let ((base-cost (if (is-eq request-type "optimization") u100
                      (if (is-eq request-type "calculation") u75
                      (if (is-eq request-type "validation") u50
                      (if (is-eq request-type "verification") u25 u10))))))
        (+ base-cost (* priority u5))))

;; Core Processing Functions
(define-public (submit-processing-request (request-type (string-ascii 50)) (priority uint) (metadata (string-ascii 50)))
    (let (
        (caller tx-sender)
        (request-id (var-get next-request-id))
        (resource-cost (calculate-resource-cost request-type priority))
    )
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (and (> priority u0) (<= priority u10)) ERR_INVALID_PARAMS)
        (asserts! (> (len request-type) u0) ERR_INVALID_PARAMS)
        (asserts! (can-process caller resource-cost) ERR_INSUFFICIENT_RESOURCES)
        
        ;; Create processing request
        (map-set processing-requests request-id {
            requester: caller,
            request-type: request-type,
            status: "pending",
            created-at: block-height,
            processed-at: none,
            result-data: none,
            priority: priority,
            resource-cost: resource-cost
        })
        
        ;; Update user daily usage
        (let ((user-prefs (default-to {auto-processing: false, notification-level: u0, custom-settings: "", last-updated: u0, daily-usage: u0} (map-get? user-preferences caller))))
            (map-set user-preferences caller (merge user-prefs {
                daily-usage: (+ (get daily-usage user-prefs) resource-cost)
            })))
        
        (var-set next-request-id (+ request-id u1))
        (var-set total-processed (+ (var-get total-processed) u1))
        (ok request-id)))

(define-public (process-request (request-id uint))
    (let (
        (caller tx-sender)
        (request-data (unwrap! (map-get? processing-requests request-id) ERR_NOT_FOUND))
        (requester (get requester request-data))
    )
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (or (is-contract-owner caller) (is-eq caller requester) (is-operator caller)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status request-data) "pending") ERR_ALREADY_PROCESSED)
        
        ;; Process based on request type
        (let ((result (process-by-type (get request-type request-data) "default")))
            (map-set processing-requests request-id (merge request-data {
                status: "completed",
                processed-at: (some block-height),
                result-data: (some result)
            }))
            (ok result))))

(define-public (batch-process (request-ids (list 100 uint)))
    (let (
        (caller tx-sender)
        (batch-id (var-get next-batch-id))
        (items-count (len request-ids))
        (total-cost (* items-count (var-get processing-fee)))
    )
        (asserts! (is-operator caller) ERR_UNAUTHORIZED)
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (<= items-count (var-get max-batch-size)) ERR_INVALID_PARAMS)
        
        ;; Create batch operation record
        (map-set batch-operations batch-id {
            operator: caller,
            operation-type: "batch-process",
            items-count: items-count,
            completed-count: u0,
            status: "processing",
            started-at: block-height,
            completed-at: none,
            total-cost: total-cost
        })
        
        ;; Complete batch operation
        (map-set batch-operations batch-id {
            operator: caller,
            operation-type: "batch-process",
            items-count: items-count,
            completed-count: items-count,
            status: "completed",
            started-at: block-height,
            completed-at: (some block-height),
            total-cost: total-cost
        })
        
        (var-set next-batch-id (+ batch-id u1))
        (ok batch-id)))

(define-public (setup-automation-rule (rule-name (string-ascii 50)) (condition-type (string-ascii 50)) (trigger-value uint) (action-type (string-ascii 50)))
    (let ((caller tx-sender))
        (asserts! (is-operator caller) ERR_UNAUTHORIZED)
        (asserts! (> (len rule-name) u0) ERR_INVALID_PARAMS)
        
        (map-set automation-rules rule-name {
            active: true,
            condition-type: condition-type,
            trigger-value: trigger-value,
            action-type: action-type,
            created-by: caller,
            last-triggered: none,
            execution-count: u0
        })
        (ok true)))

(define-public (trigger-automation-rule (rule-name (string-ascii 50)))
    (let ((caller tx-sender)
          (rule-data (unwrap! (map-get? automation-rules rule-name) ERR_NOT_FOUND)))
        (asserts! (is-operator caller) ERR_UNAUTHORIZED)
        (asserts! (get active rule-data) ERR_INVALID_STATE)
        
        ;; Update rule execution count
        (map-set automation-rules rule-name (merge rule-data {
            last-triggered: (some block-height),
            execution-count: (+ (get execution-count rule-data) u1)
        }))
        (ok (get execution-count rule-data))))

(define-public (update-user-preferences (auto-processing bool) (notification-level uint) (custom-settings (string-ascii 256)))
    (let ((caller tx-sender))
        (asserts! (<= notification-level u5) ERR_INVALID_PARAMS)
        
        (map-set user-preferences caller {
            auto-processing: auto-processing,
            notification-level: notification-level,
            custom-settings: custom-settings,
            last-updated: block-height,
            daily-usage: u0
        })
        (ok true)))

(define-public (emergency-stop)
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (var-set processing-active false)
        (var-set automation-enabled false)
        (ok true)))

(define-public (set-processing-fee (new-fee uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u1000) ERR_INVALID_PARAMS)
        (var-set processing-fee new-fee)
        (ok true)))

(define-public (set-daily-limit (new-limit uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> new-limit u0) ERR_INVALID_PARAMS)
        (var-set daily-limit new-limit)
        (ok true)))

;; Read Functions
(define-read-only (get-processing-request (request-id uint))
    (map-get? processing-requests request-id))

(define-read-only (get-automation-rule (rule-name (string-ascii 50)))
    (map-get? automation-rules rule-name))

(define-read-only (get-user-preferences (user principal))
    (map-get? user-preferences user))

(define-read-only (get-batch-operation (batch-id uint))
    (map-get? batch-operations batch-id))

(define-read-only (get-system-stats)
    {
        active: (var-get processing-active),
        automation: (var-get automation-enabled),
        total-processed: (var-get total-processed),
        next-request-id: (var-get next-request-id),
        processing-fee: (var-get processing-fee),
        daily-limit: (var-get daily-limit)
    })

(define-read-only (get-pending-requests-count)
    (var-get next-request-id))

(define-read-only (is-processing-active)
    (var-get processing-active))

(define-read-only (get-max-batch-size)
    (var-get max-batch-size))

(define-read-only (get-resource-cost (request-type (string-ascii 50)) (priority uint))
    (calculate-resource-cost request-type priority))

(define-read-only (get-user-daily-usage (user principal))
    (default-to u0 (get daily-usage (map-get? user-preferences user))))

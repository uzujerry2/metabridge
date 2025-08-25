;; Meta Bridge - Cross-Chain NFT Bridge with Fractional Ownership
;; Features: NFT bridging, fractional shares, royalty streaming, DAO governance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-nft-not-found (err u101))
(define-constant err-already-bridged (err u102))
(define-constant err-insufficient-shares (err u103))
(define-constant err-invalid-chain (err u104))
(define-constant err-bridge-paused (err u105))
(define-constant err-already-claimed (err u106))
(define-constant err-invalid-signature (err u107))
(define-constant err-expired-request (err u108))
(define-constant err-insufficient-votes (err u109))
(define-constant err-proposal-active (err u110))
(define-constant err-max-supply (err u111))
(define-constant err-invalid-amount (err u112))

;; Protocol Parameters
(define-constant max-fractions u10000) ;; Maximum fractional shares per NFT
(define-constant min-fraction-trade u100) ;; Minimum 1% share trade
(define-constant bridge-fee u50) ;; 0.5% bridge fee (basis points)
(define-constant royalty-fee u250) ;; 2.5% royalty fee
(define-constant validator-threshold u3) ;; 3 validators required
(define-constant proposal-duration u1440) ;; ~10 days for proposals
(define-constant quorum-percentage u3000) ;; 30% quorum required
(define-constant grace-period u144) ;; ~24 hours grace period

;; Supported chains
(define-constant chain-ethereum u1)
(define-constant chain-bsc u2)
(define-constant chain-polygon u3)
(define-constant chain-solana u4)
(define-constant chain-bitcoin u5)

;; Data Variables
(define-data-var nft-counter uint u0)
(define-data-var bridge-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var total-volume uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var bridge-paused bool false)
(define-data-var emergency-mode bool false)

;; Data Maps
(define-map bridged-nfts
    uint ;; nft-id
    {
        original-chain: uint,
        original-contract: (string-ascii 66),
        original-token-id: uint,
        owner: principal,
        metadata-uri: (string-ascii 256),
        is-fractionalized: bool,
        total-shares: uint,
        available-shares: uint,
        royalty-recipient: principal,
        royalty-percentage: uint,
        bridge-time: uint,
        is-locked: bool
    })

(define-map fractional-ownership
    { nft-id: uint, owner: principal }
    {
        shares: uint,
        acquired-at: uint,
        last-claim: uint,
        total-dividends: uint
    })

(define-map bridge-requests
    uint ;; request-id
    {
        nft-id: uint,
        from-chain: uint,
        to-chain: uint,
        requester: principal,
        amount: uint,
        status: (string-ascii 20),
        created-at: uint,
        completed-at: uint,
        validator-count: uint
    })

(define-map validator-signatures
    { request-id: uint, validator: principal }
    {
        signed: bool,
        signed-at: uint,
        signature: (buff 65)
    })

(define-map authorized-validators
    principal
    {
        is-active: bool,
        total-validated: uint,
        reputation: uint,
        added-at: uint
    })

(define-map royalty-pools
    uint ;; nft-id
    {
        total-royalties: uint,
        unclaimed-royalties: uint,
        last-distribution: uint,
        total-distributions: uint
    })

(define-map governance-proposals
    uint ;; proposal-id
    {
        proposer: principal,
        proposal-type: (string-ascii 20),
        description: (string-ascii 500),
        target-value: uint,
        votes-for: uint,
        votes-against: uint,
        start-block: uint,
        end-block: uint,
        executed: bool,
        execution-delay: uint
    })

(define-map user-votes
    { proposal-id: uint, voter: principal }
    {
        vote-weight: uint,
        voted-for: bool,
        voted-at: uint
    })

(define-map chain-configs
    uint ;; chain-id
    {
        is-enabled: bool,
        min-confirmations: uint,
        fee-multiplier: uint,
        total-bridged: uint
    })

;; Initialize chain configurations
(map-set chain-configs chain-ethereum { is-enabled: true, min-confirmations: u12, fee-multiplier: u100, total-bridged: u0 })
(map-set chain-configs chain-bsc { is-enabled: true, min-confirmations: u15, fee-multiplier: u80, total-bridged: u0 })
(map-set chain-configs chain-polygon { is-enabled: true, min-confirmations: u30, fee-multiplier: u60, total-bridged: u0 })
(map-set chain-configs chain-solana { is-enabled: true, min-confirmations: u1, fee-multiplier: u90, total-bridged: u0 })
(map-set chain-configs chain-bitcoin { is-enabled: true, min-confirmations: u6, fee-multiplier: u150, total-bridged: u0 })

;; Private Functions
(define-private (calculate-bridge-fee (amount uint) (chain uint))
    (match (map-get? chain-configs chain)
        config (/ (* (* amount bridge-fee) (get fee-multiplier config)) u1000000)
        (/ (* amount bridge-fee) u10000)))

(define-private (calculate-royalty (sale-price uint) (royalty-percentage uint))
    (/ (* sale-price royalty-percentage) u10000))

(define-private (distribute-royalties (nft-id uint) (amount uint))
    (match (map-get? royalty-pools nft-id)
        pool (map-set royalty-pools nft-id
                     (merge pool {
                         total-royalties: (+ (get total-royalties pool) amount),
                         unclaimed-royalties: (+ (get unclaimed-royalties pool) amount),
                         last-distribution: burn-block-height
                     }))
        (map-set royalty-pools nft-id {
            total-royalties: amount,
            unclaimed-royalties: amount,
            last-distribution: burn-block-height,
            total-distributions: u0
        })))

(define-private (calculate-voting-power (user principal))
    (let ((nft-count (var-get nft-counter)))
        u1000)) ;; Simplified - in production, calculate based on holdings

(define-private (is-validator (validator principal))
    (match (map-get? authorized-validators validator)
        validator-info (get is-active validator-info)
        false))

;; Read-only Functions
(define-read-only (get-nft-info (nft-id uint))
    (ok (map-get? bridged-nfts nft-id)))

(define-read-only (get-fractional-balance (nft-id uint) (owner principal))
    (ok (map-get? fractional-ownership { nft-id: nft-id, owner: owner })))

(define-read-only (get-bridge-request (request-id uint))
    (ok (map-get? bridge-requests request-id)))

(define-read-only (get-royalty-pool (nft-id uint))
    (ok (map-get? royalty-pools nft-id)))

(define-read-only (get-proposal (proposal-id uint))
    (ok (map-get? governance-proposals proposal-id)))

(define-read-only (get-chain-config (chain uint))
    (ok (map-get? chain-configs chain)))

(define-read-only (calculate-claimable-royalties (nft-id uint) (owner principal))
    (match (map-get? fractional-ownership { nft-id: nft-id, owner: owner })
        ownership (match (map-get? royalty-pools nft-id)
                    pool (match (map-get? bridged-nfts nft-id)
                            nft (let ((share-percentage (/ (* (get shares ownership) u10000) 
                                                          (get total-shares nft))))
                                    (ok (/ (* (get unclaimed-royalties pool) share-percentage) u10000)))
                            (err err-nft-not-found))
                    (ok u0))
        (ok u0)))

(define-read-only (get-protocol-stats)
    (ok {
        total-nfts: (var-get nft-counter),
        total-bridges: (var-get bridge-counter),
        total-volume: (var-get total-volume),
        total-fees: (var-get total-fees-collected),
        is-paused: (var-get bridge-paused)
    }))

;; Public Functions
(define-public (bridge-nft (original-chain uint) 
                          (original-contract (string-ascii 66))
                          (original-token-id uint)
                          (metadata-uri (string-ascii 256))
                          (royalty-percentage uint))
    (let ((nft-id (+ (var-get nft-counter) u1))
          (chain-config (unwrap! (map-get? chain-configs original-chain) err-invalid-chain)))
        
        ;; Validations
        (asserts! (not (var-get bridge-paused)) err-bridge-paused)
        (asserts! (get is-enabled chain-config) err-invalid-chain)
        (asserts! (<= royalty-percentage u1000) err-invalid-amount) ;; Max 10% royalty
        
        ;; Create bridged NFT
        (map-set bridged-nfts nft-id {
            original-chain: original-chain,
            original-contract: original-contract,
            original-token-id: original-token-id,
            owner: tx-sender,
            metadata-uri: metadata-uri,
            is-fractionalized: false,
            total-shares: max-fractions,
            available-shares: max-fractions,
            royalty-recipient: tx-sender,
            royalty-percentage: royalty-percentage,
            bridge-time: burn-block-height,
            is-locked: false
        })
        
        ;; Initialize royalty pool
        (map-set royalty-pools nft-id {
            total-royalties: u0,
            unclaimed-royalties: u0,
            last-distribution: burn-block-height,
            total-distributions: u0
        })
        
        ;; Update chain config
        (map-set chain-configs original-chain
                (merge chain-config {
                    total-bridged: (+ (get total-bridged chain-config) u1)
                }))
        
        ;; Update counters
        (var-set nft-counter nft-id)
        (var-set bridge-counter (+ (var-get bridge-counter) u1))
        
        (ok nft-id)))

(define-public (fractionalize-nft (nft-id uint) (shares-to-keep uint))
    (let ((nft (unwrap! (map-get? bridged-nfts nft-id) err-nft-not-found)))
        
        ;; Validations
        (asserts! (is-eq tx-sender (get owner nft)) err-unauthorized)
        (asserts! (not (get is-fractionalized nft)) err-already-bridged)
        (asserts! (<= shares-to-keep max-fractions) err-invalid-amount)
        (asserts! (>= shares-to-keep min-fraction-trade) err-invalid-amount)
        
        ;; Update NFT
        (map-set bridged-nfts nft-id
                (merge nft {
                    is-fractionalized: true,
                    available-shares: (- max-fractions shares-to-keep)
                }))
        
        ;; Assign shares to owner
        (map-set fractional-ownership 
                { nft-id: nft-id, owner: tx-sender }
                {
                    shares: shares-to-keep,
                    acquired-at: burn-block-height,
                    last-claim: burn-block-height,
                    total-dividends: u0
                })
        
        (ok true)))

(define-public (trade-fractions (nft-id uint) (shares uint) (recipient principal))
    (let ((nft (unwrap! (map-get? bridged-nfts nft-id) err-nft-not-found))
          (sender-ownership (unwrap! (map-get? fractional-ownership { nft-id: nft-id, owner: tx-sender })
                                    err-insufficient-shares))
          (recipient-ownership (default-to { shares: u0, acquired-at: burn-block-height, 
                                            last-claim: burn-block-height, total-dividends: u0 }
                                          (map-get? fractional-ownership { nft-id: nft-id, owner: recipient }))))
        
        ;; Validations
        (asserts! (get is-fractionalized nft) err-unauthorized)
        (asserts! (>= (get shares sender-ownership) shares) err-insufficient-shares)
        (asserts! (>= shares min-fraction-trade) err-invalid-amount)
        
        ;; Update sender
        (map-set fractional-ownership 
                { nft-id: nft-id, owner: tx-sender }
                (merge sender-ownership {
                    shares: (- (get shares sender-ownership) shares)
                }))
        
        ;; Update recipient
        (map-set fractional-ownership 
                { nft-id: nft-id, owner: recipient }
                (merge recipient-ownership {
                    shares: (+ (get shares recipient-ownership) shares)
                }))
        
        (ok true)))

(define-public (claim-royalties (nft-id uint))
    (let ((ownership (unwrap! (map-get? fractional-ownership { nft-id: nft-id, owner: tx-sender })
                             err-unauthorized))
          (pool (unwrap! (map-get? royalty-pools nft-id) err-nft-not-found))
          (nft (unwrap! (map-get? bridged-nfts nft-id) err-nft-not-found))
          (share-percentage (/ (* (get shares ownership) u10000) (get total-shares nft)))
          (claimable (/ (* (get unclaimed-royalties pool) share-percentage) u10000)))
        
        ;; Validations
        (asserts! (> claimable u0) err-invalid-amount)
        
        ;; Transfer royalties
        (try! (as-contract (stx-transfer? claimable tx-sender tx-sender)))
        
        ;; Update pool
        (map-set royalty-pools nft-id
                (merge pool {
                    unclaimed-royalties: (- (get unclaimed-royalties pool) claimable),
                    total-distributions: (+ (get total-distributions pool) u1)
                }))
        
        ;; Update ownership
        (map-set fractional-ownership 
                { nft-id: nft-id, owner: tx-sender }
                (merge ownership {
                    last-claim: burn-block-height,
                    total-dividends: (+ (get total-dividends ownership) claimable)
                }))
        
        (ok claimable)))

(define-public (initiate-bridge-transfer (nft-id uint) (to-chain uint) (amount uint))
    (let ((request-id (+ (var-get bridge-counter) u1))
          (nft (unwrap! (map-get? bridged-nfts nft-id) err-nft-not-found))
          (chain-config (unwrap! (map-get? chain-configs to-chain) err-invalid-chain))
          (fee (calculate-bridge-fee amount to-chain)))
        
        ;; Validations
        (asserts! (not (var-get bridge-paused)) err-bridge-paused)
        (asserts! (get is-enabled chain-config) err-invalid-chain)
        (asserts! (not (get is-locked nft)) err-already-bridged)
        
        ;; Pay bridge fee
        (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
        
        ;; Create bridge request
        (map-set bridge-requests request-id {
            nft-id: nft-id,
            from-chain: chain-stacks,
            to-chain: to-chain,
            requester: tx-sender,
            amount: amount,
            status: "pending",
            created-at: burn-block-height,
            completed-at: u0,
            validator-count: u0
        })
        
        ;; Lock NFT during bridging
        (map-set bridged-nfts nft-id
                (merge nft { is-locked: true }))
        
        ;; Update stats
        (var-set bridge-counter request-id)
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        
        (ok request-id)))

(define-public (validate-bridge (request-id uint) (signature (buff 65)))
    (let ((request (unwrap! (map-get? bridge-requests request-id) err-invalid-signature))
          (validator-info (unwrap! (map-get? authorized-validators tx-sender) err-unauthorized)))
        
        ;; Validations
        (asserts! (get is-active validator-info) err-unauthorized)
        (asserts! (is-eq (get status request) "pending") err-already-claimed)
        (asserts! (is-none (map-get? validator-signatures { request-id: request-id, validator: tx-sender }))
                 err-already-claimed)
        
        ;; Record signature
        (map-set validator-signatures 
                { request-id: request-id, validator: tx-sender }
                {
                    signed: true,
                    signed-at: burn-block-height,
                    signature: signature
                })
        
        ;; Update request
        (let ((new-count (+ (get validator-count request) u1)))
            (map-set bridge-requests request-id
                    (merge request {
                        validator-count: new-count,
                        status: (if (>= new-count validator-threshold) "validated" "pending")
                    }))
            
            ;; Update validator stats
            (map-set authorized-validators tx-sender
                    (merge validator-info {
                        total-validated: (+ (get total-validated validator-info) u1),
                        reputation: (+ (get reputation validator-info) u1)
                    }))
            
            (ok (>= new-count validator-threshold)))))

(define-public (complete-bridge (request-id uint))
    (let ((request (unwrap! (map-get? bridge-requests request-id) err-invalid-signature))
          (nft (unwrap! (map-get? bridged-nfts (get nft-id request)) err-nft-not-found)))
        
        ;; Validations
        (asserts! (is-eq (get status request) "validated") err-insufficient-votes)
        (asserts! (is-eq tx-sender (get requester request)) err-unauthorized)
        
        ;; Complete bridge
        (map-set bridge-requests request-id
                (merge request {
                    status: "completed",
                    completed-at: burn-block-height
                }))
        
        ;; Unlock NFT
        (map-set bridged-nfts (get nft-id request)
                (merge nft { is-locked: false }))
        
        ;; Update volume
        (var-set total-volume (+ (var-get total-volume) (get amount request)))
        
        (ok true)))

(define-public (create-proposal (proposal-type (string-ascii 20)) 
                               (description (string-ascii 500))
                               (target-value uint))
    (let ((proposal-id (+ (var-get proposal-counter) u1))
          (voting-power (calculate-voting-power tx-sender)))
        
        ;; Validations
        (asserts! (> voting-power u0) err-unauthorized)
        
        ;; Create proposal
        (map-set governance-proposals proposal-id {
            proposer: tx-sender,
            proposal-type: proposal-type,
            description: description,
            target-value: target-value,
            votes-for: u0,
            votes-against: u0,
            start-block: burn-block-height,
            end-block: (+ burn-block-height proposal-duration),
            executed: false,
            execution-delay: grace-period
        })
        
        ;; Update counter
        (var-set proposal-counter proposal-id)
        
        (ok proposal-id)))

(define-public (vote-proposal (proposal-id uint) (vote-for bool))
    (let ((proposal (unwrap! (map-get? governance-proposals proposal-id) err-invalid-signature))
          (voting-power (calculate-voting-power tx-sender)))
        
        ;; Validations
        (asserts! (< burn-block-height (get end-block proposal)) err-expired-request)
        (asserts! (not (get executed proposal)) err-already-claimed)
        (asserts! (is-none (map-get? user-votes { proposal-id: proposal-id, voter: tx-sender }))
                 err-already-claimed)
        
        ;; Record vote
        (map-set user-votes 
                { proposal-id: proposal-id, voter: tx-sender }
                {
                    vote-weight: voting-power,
                    voted-for: vote-for,
                    voted-at: burn-block-height
                })
        
        ;; Update proposal
        (map-set governance-proposals proposal-id
                (merge proposal {
                    votes-for: (if vote-for 
                                 (+ (get votes-for proposal) voting-power)
                                 (get votes-for proposal)),
                    votes-against: (if vote-for
                                     (get votes-against proposal)
                                     (+ (get votes-against proposal) voting-power))
                }))
        
        (ok true)))

(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (map-set authorized-validators validator {
            is-active: true,
            total-validated: u0,
            reputation: u1000,
            added-at: burn-block-height
        })
        (ok true)))

;; Admin Functions
(define-public (pause-bridge)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set bridge-paused true)
        (ok true)))

(define-public (unpause-bridge)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set bridge-paused false)
        (ok true)))

(define-public (update-chain-config (chain uint) (enabled bool) (fee-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (match (map-get? chain-configs chain)
            config (map-set chain-configs chain
                          (merge config {
                              is-enabled: enabled,
                              fee-multiplier: fee-multiplier
                          }))
            true)
        (ok true)))

(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= amount (var-get total-fees-collected)) err-insufficient-shares)
        (var-set total-fees-collected (- (var-get total-fees-collected) amount))
        (as-contract (stx-transfer? amount tx-sender contract-owner))))

;; Add missing constant
(define-constant chain-stacks u0)
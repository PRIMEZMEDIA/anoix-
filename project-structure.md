anoix/
├── app/
│   ├── Core/               # framework primitives
│   ├── Controllers/
│   ├── Models/
│   ├── Middleware/
│   └── Views/
├── config/
│   ├── config.php
│   └── routes.php
├── database/
│   ├── migrations/
│   └── seeds/
├── public/                 # web root (only this is exposed)
│   ├── index.php
│   ├── .htaccess
│   ├── robots.txt
│   ├── sitemap.xml
│   ├── llms.txt
│   ├── manifest.webmanifest
│   ├── sw.js
│   └── assets/{css,js,img}/
├── storage/
│   └── logs/
├── tests/
├── .env.example
└── README.md


anoix/
├── app/
│   ├── Core/Storage.php                          [NEW]
│   ├── Controllers/
│   │   ├── DocumentController.php                [NEW]
│   │   ├── DistributorVerificationController.php [NEW]
│   │   └── OpsVerificationController.php         [NEW]
│   ├── Models/
│   │   ├── DistributorProfile.php                [EDIT — add stage helpers]
│   │   ├── DistributorDocument.php               [NEW]
│   │   ├── VerificationReview.php                [NEW]
│   │   └── VerificationAppeal.php                [NEW]
│   └── Views/
│       ├── partials/verification_badge.php       [NEW]
│       ├── dashboard/index.php                   [EDIT — add verification panel]
│       └── verification/
│           ├── distributor.php                   [NEW]
│           ├── ops_queue.php                     [NEW]
│           ├── ops_review.php                    [NEW]
│           ├── ops_appeals.php                   [NEW]
│           └── ops_appeal_review.php             [NEW]
├── config/routes.php                             [EDIT — add routes]
├── database/
│   ├── migrations/002_verification.sql           [NEW]
│   └── seeds/002_verification_settings.sql       [NEW]
└── storage/uploads/                              [NEW dir + .gitignore]
    └── documents/2026/...

    anoix/
├── app/
│   ├── Core/Money.php                                    [NEW]
│   ├── Models/
│   │   ├── Listing.php                                   [NEW]
│   │   ├── Order.php                                     [NEW]
│   │   └── OrderEvent.php                                [NEW]
│   ├── Controllers/
│   │   ├── DiscoverController.php                        [NEW]
│   │   ├── OrderController.php                           [NEW]
│   │   └── DistributorListingController.php              [NEW]
│   └── Views/
│       ├── partials/order_status.php                     [NEW]
│       ├── partials/order_timeline.php                   [NEW]
│       ├── discover/index.php                            [NEW]
│       ├── discover/show.php                             [NEW]
│       ├── orders/index.php                              [NEW]
│       ├── orders/show.php                               [NEW]
│       ├── orders/new.php                                [NEW]
│       ├── distributor/listings.php                      [NEW]
│       └── dashboard/index.php                           [EDIT]
├── config/routes.php                                     [EDIT]
├── database/
│   ├── migrations/003_orders.sql                         [NEW]
│   └── seeds/003_marketplace_settings.sql                [NEW]
├── public/assets/css/app.css                             [EDIT]
└── app/Controllers/SeoController.php                     [EDIT — /discover in sitemap]

anoix/
├── app/
│   ├── Payments/
│   │   ├── ProviderResult.php                    [NEW]
│   │   ├── PaymentProviderInterface.php          [NEW]
│   │   ├── PaymentProvider.php                   [NEW — registry/factory]
│   │   ├── Providers/
│   │   │   └── MockPaymentProvider.php           [NEW]
│   │   ├── Ledger.php                            [NEW — double-entry, append-only]
│   │   ├── PaymentService.php                    [NEW]
│   │   └── WebhookService.php                    [NEW]
│   ├── Models/
│   │   ├── Payment.php                           [NEW]
│   │   └── PaymentWebhookEvent.php               [NEW]
│   ├── Controllers/
│   │   ├── PaymentController.php                 [NEW]
│   │   ├── PaymentWebhookController.php          [NEW]
│   │   └── DevMockProviderController.php         [NEW — dev-only]
│   └── Views/
│       ├── partials/payment_status.php           [NEW]
│       ├── partials/payment_timeline.php         [NEW]
│       ├── payments/show.php                     [NEW]
│       ├── payments/checkout.php                 [NEW]
│       ├── orders/show.php                       [EDIT]
│       └── dashboard/index.php                   [EDIT]
├── config/config.php                             [EDIT — payments block]
├── config/routes.php                             [EDIT]
├── database/
│   ├── migrations/004_payments.sql               [NEW]
│   └── seeds/004_payment_settings.sql            [NEW]
└── public/assets/css/app.css                     [EDIT]
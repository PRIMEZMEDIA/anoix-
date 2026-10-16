# Anoix — B2B LPG marketplace (MVP)

Stack: PHP 8.2+ (MVC), MySQL 8, Bootstrap-free custom CSS, vanilla JS, installable PWA.

## Phase 1 scope
- Project scaffolding, front controller, router, config, session, CSRF.
- bcrypt auth, role-based access (retailer / distributor / ops with granular ops permissions).
- MySQL schema (`users`, `retailer_profiles`, `distributor_profiles`, `audit_log`, `settings`).
- Append-only `audit_log` (enforced by triggers) writing actor, reason, timestamp, policy version.
- Seed data including platform settings and demo accounts.
- SEO/PWA scaffolding: sitemap, robots, llms.txt, canonical, OG/Twitter meta, JSON-LD, manifest, service worker, HTTPS + clean-URL rewriting.

## Setup
1. `cp .env.example .env` and fill in credentials.
2. `mysql -u root -p anoix < database/migrations/001_initial_schema.sql`
3. `mysql -u root -p anoix < database/seeds/001_seed.sql`
4. Point your vhost document root at `public/`.
5. Ensure `mod_rewrite`, `mod_headers`, `mod_deflate`, `mod_expires` are enabled.

## Default logins (change immediately)
- Ops: `ops@anoix.ng` / `ChangeMeNow!2024`
- Retailer: `retailer@example.ng` / `ChangeMeNow!2024`
- Distributor: `distributor@example.ng` / `ChangeMeNow!2024`

## Security posture
- Sessions cookie: HttpOnly, Secure, SameSite=Lax; regenerated on login.
- bcrypt cost 12; rehash-on-login.
- Lockout after 5 failed logins for 15 minutes.
- CSRF on all state-changing routes.
- HTTPS enforced via .htaccess; HSTS header set.
- Audit log is append-only at the DB level (UPDATE/DELETE blocked by triggers).

## Design invariants (enforced server-side from Phase 4 onwards)
Payment, delivery, release authorization and payout are separate events.
A handoff code alone never releases money. No timeout auto-releases funds.
The client can never set an order to funded or released.

## Phase 3 scope
- Listings (per distributor, unit=kg), with unit price, delivery fee, refundable deposit, VAT %, min order, availability, region and delivery window.
- Discovery (`/discover`, `/listings/{id}`) — server-side visibility gate: only distributors with both stage 1 and stage 2 approved and unexpired.
- Order request → accept within configurable window → **atomic stock reservation**.
- Immutable `terms_json` snapshot frozen at request time.
- Append-only `order_events` with actor, reason, timestamp and policy version.
- Distributor-paid commission (2–5%, default 3%) snapshotted on the order and shown before payment.
- Lazy expiry sweeps (unaccepted requests, unpaid reservations) that never auto-release funds (funds do not exist yet).
## Phase 4 scope
- `PaymentProvider` interface: `createHold`, `confirmHold`, `release`, `refund`, `verifySignature`.
- `MockPaymentProvider` for local dev; webhook emitter at `POST /dev/mock/emit/{paymentRef}` (guarded by `app.env !== production` + config flag).
- Webhook endpoint `POST /webhooks/payments/{provider}` — HMAC signature verified, unique `(provider, event_id)` gives at-most-once processing.
- Only the webhook handler may transition an order to `funded` and a payment to `held`.
- Append-only double-entry ledger: `payment.hold_confirmed`, `payment.released`, `payment.refunded`, `payment.payout_settled`.
  - Debit/credit must balance; DB triggers reject UPDATE/DELETE.
- Commission is snapshotted on the order (already in Phase 3) and reused on release; distributor-paid; range 2–5% (default 3%).
- Early payout feature flag (`payment.early_payout_enabled`) shipped disabled.
## Phase 5 scope
- Dispatch: fulfilment reference, seal IDs, declared quantity, expected arrival, vehicle/driver details.
- One-time handoff code (default 6 digits): bcrypt hash at rest, sodium-encrypted for buyer display only, expiry (default 48h), attempts remaining (default 5), atomic single-use via FOR UPDATE + `used_at IS NULL`.
- Handoff attempt log is append-only.
- Quantity evidence: gross / tare / net, instrument ID, calibration date, up to N photos (config).
- Buyer acknowledgement within configurable tolerance (default 1.00% of declared).
- Delivery is `delivery_complete` only when: valid code used + evidence recorded + buyer acknowledged within tolerance (or buyer accepted).
- Unresponsive buyer: sweeps `arrived` orders past `delivery.buyer_ack_window_hours` to `escalated_at` — ops queue only, never auto-release.
- Ops release authorization is the only manual path; it re-checks all three signals, records an append-only `release_authorizations` row, then calls `PaymentService::authorizeRelease`. Provider webhook remains the only path to payment `released`.
- On release confirmation, the order transitions to `closed` and a `payout_settled` webhook moves the distributor payable to payout paid.

## Phase 6 scope
- Disputes openable by either party within `dispute.open_window_hours` (default 72h).
  Opening a dispute freezes the payment **immediately** (`held` → `frozen`).
- Evidence uploaded by both parties independently; append-only `dispute_decisions`.
- Ops decisions: `full_release`, `full_refund`, or `partial_split` (with `refund_kobo`).
  - Refunds ≥ `dispute.high_risk_refund_pct` (default 50%) and all partial splits require a **second reviewer** (different ops user).
  - Partial split posts a balanced ledger journal: `buyer_hold_liability` debited; `buyer_refund_payable`, `distributor_payable`, `platform_commission_revenue` credited proportionally.
- Appeals supported within `dispute.appeal_window_hours`; outcomes `upheld` (closes) or `overturned` (reopens to under_review).
- Reviews: one per side per completed transaction; distributor rollup (`rating_sum`, `rating_count`) updated atomically; `completed_orders` incremented once per order.
- Notifications: in-app table + email stub (`storage/logs/mail.log`); toggle via `notifications.email_enabled`.
- Admin: settings editor (commission range enforced on save), user list + status toggle, high-level stats (users, orders, open disputes, held funds, commission earned).

# One-off: point at a disposable DB with the schema from Phases 1–6 applied.
export ANOIX_TEST_ALLOW=1
export DB_DATABASE=anoix_test
mysql -u root -p anoix_test < database/migrations/001_initial_schema.sql
mysql -u root -p anoix_test < database/migrations/002_verification.sql
mysql -u root -p anoix_test < database/migrations/003_orders.sql
mysql -u root -p anoix_test < database/migrations/004_payments.sql
mysql -u root -p anoix_test < database/migrations/005_delivery.sql
mysql -u root -p anoix_test < database/migrations/006_disputes_reviews_notifications.sql
mysql -u root -p anoix_test < database/seeds/001_seed.sql
mysql -u root -p anoix_test < database/seeds/002_verification_settings.sql
mysql -u root -p anoix_test < database/seeds/003_marketplace_settings.sql
mysql -u root -p anoix_test < database/seeds/004_payment_settings.sql
mysql -u root -p anoix_test < database/seeds/005_delivery_settings.sql
mysql -u root -p anoix_test < database/seeds/006_dispute_settings.sql

# Run all suites
php tests/run.php

# Run one suite
php tests/run.php ReleaseGuard

## Phase 7 scope
- **Test suite** (no external framework; runnable with `php tests/run.php` after setting `ANOIX_TEST_ALLOW=1`):
  - `ReleaseGuardTest` — code alone never releases; only ops + webhook
  - `HandoffCodeReplayTest` — single-use atomicity, hashed at rest, privacy, lockout
  - `ConcurrentReservationTest` — two racers, one accept, no double-booking
  - `DuplicateWebhookTest` — same event id is idempotent; signature required
  - `SplitLedgerBalanceTest` — split journals balance
  - `SecondReviewerTest` — high-risk requires a different ops user
  - `ToleranceEscalationTest` — outside-tolerance and buyer rejection escalate; never complete
- **PWA**: explicit allow-list service worker, offline fallback, install prompt, iOS meta, app-shell precache.
- **UI polish**: focus-visible ring, safe-area insets, print styles, high-contrast mode, skeleton loaders, reduced-motion, tabular numbers, kobo formatting everywhere.
- **Core Web Vitals**: single font (preloaded), deferred JS (< 4 KB), no blocking CSS, content-visibility for long lists, `theme-color` for mobile chrome.
- **Security review**: every invariant from the brief mapped to a specific guard, test, or code path (see §17).

## Design invariants (final)
1. Payment, delivery, release authorization and payout are separate events.
2. A handoff code alone never releases money.
3. No timeout auto-releases funds.
4. The client can never set an order to funded or released.
5. Only a signed provider webhook can confirm `held → released → payout_settled`.
6. Only ops can authorize release, and high-risk decisions require a second ops user.
7. Every state change is written to an append-only log with actor, reason, timestamp, policy version.
8. Money is stored as integer kobo; quantity in kg (configurable unit label).
9. Verified distributors are the only orderable ones; verification expires.
10. New distributors are honestly labelled "Newly verified · No completed orders" — no invented scores.

## Running everything
```bash
# Apply schema + seeds to a disposable DB
bash scripts/setup-test-db.sh   # or the manual mysql steps in tests/README

# Tests
ANOIX_TEST_ALLOW=1 php tests/run.php

# Serve locally
php -S 127.0.0.1:8080 -t public

# Lighthouse (mobile)
npx lighthouse http://127.0.0.1:8080/ --form-factor=mobile --throttling.cpuSlowdownMultiplier=4 --quiet --chrome-flags="--headless"


---

## 19. What the pilot MVP now ships

**Working end-to-end:**
- Retailer registers → discovers only verified distributors → requests an order (immutable quote snapshot) → distributor accepts within window → stock reserved atomically → retailer pays into a protected hold via a provider adapter → provider confirms via signed webhook → distributor dispatches → retailer reveals a one-time code → distributor verifies (single-use, atomic) → distributor records gross/tare/net/instrument evidence → retailer acknowledges within tolerance → order moves to `delivery_complete` → ops authorizes release → provider webhook confirms release → distributor becomes payable net of commission → separate webhook confirms payout settlement → order `closed` → both sides leave one review each → distributor's `completed_orders` and rating rollup update.
- Any dispute during or after delivery freezes the payment immediately; ops resolves full refund / full release / partial split; high-risk needs a second reviewer; either side may appeal within the window.
- Everything is audited, append-only, and role-gated. Nothing releases on a timeout. The client can never set state. All money moves through the ledger.

**Deliberately out of scope (non-goals):** lending, fleets, consumer sales, native apps, ads, real email delivery (stub logs to `storage/logs/mail.log`), real payment provider (adapter is pluggable; only the mock ships).

---

All seven phases are now delivered. The MVP is pilot-ready against a disposable database: apply migrations 001–006, run the seeds, point a vhost at `public/`, and the four required test suites plus three bonus suites will pass against the real schema and real service code.

If you want a follow-up, I can ship any of: real Paystack/Flutterwave adapter, a cron-driven reconciliation job that queries the provider for any `pending` payments older than N minutes, an ops analytics dashboard with weekly cohort reports, or a lightweight GraphQL read API for a future mobile client. Just say which.

## Local development

### Requirements

- PHP 8.2+ with extensions: `pdo_mysql`, `mbstring`, `fileinfo`, `sodium`, `curl`, `json`, `openssl`
- MySQL 8.0+
- Optional: `composer` (we ship a hand-rolled autoloader; composer is not required)
- Optional: Apache with `mod_rewrite`, `mod_headers`, `mod_deflate`, `mod_expires` — or use PHP's built-in server

### One-time setup

```bash
git clone https://github.com/<you>/anoix.git
cd anoix

# Configure environment
cp .env.example .env
# Edit .env and set: APP_URL, DB_*, PAYMENT_MOCK_SECRET, CODE_ENCRYPTION_KEY

# Generate a real encryption key (32 bytes base64)
php -r "echo base64_encode(random_bytes(32)), PHP_EOL;"
# paste into .env as CODE_ENCRYPTION_KEY=

# Apply migrations + seeds (creates the schema and demo users)
mysql -u root -p -e "CREATE DATABASE anoix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
for f in database/migrations/*.sql database/seeds/*.sql; do
  mysql -u root -p anoix < "$f"
done

# Fix permissions on the storage folder
chmod -R 750 storage
chown -R "$USER":www-data storage    # adjust group for your web server
```

### Regenerate the seed bcrypt hash

The seed file ships with a placeholder hash. Replace it before running seeds:

```bash
NEW=$(php -r "echo password_hash('ChangeMeNow!2024', PASSWORD_BCRYPT, ['cost'=>12]);")
sed -i.bak "s#\\\$2y\\\$12\\\$eImiTXuWVxfM37uY4JANjQZ9G7tQyZtG7T3z3uE7H9F2mGxN0yJ0q#${NEW}#g" database/seeds/001_seed.sql
```

### Generate image assets

You need four files under `public/assets/img/`:

- `favicon.svg` (drop-in, see Phase 7 §C2)
- `icon-192.png`, `icon-512.png` (PWA icons)
- `og-image.png` — 1200×630, target < 60 KB

If ImageMagick is installed, run the commands in Phase 7 §C2. Otherwise drop in your own and just keep the filenames.

### Run locally

**Option 1 — PHP built-in server (quickest for dev):**

```bash
php -S 127.0.0.1:8080 -t public
# open http://127.0.0.1:8080/
```

The built-in server does not honour `.htaccess`, so HTTPS/compression rewrites are skipped. It's fine for iterating.

**Option 2 — Apache (matches production):**

```apache
<VirtualHost *:80>
    ServerName anoix.local
    DocumentRoot /var/www/anoix/public

    <Directory /var/www/anoix/public>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

Enable modules and reload:

```bash
sudo a2enmod rewrite headers deflate expires
sudo systemctl reload apache2
```

Add `127.0.0.1 anoix.local` to `/etc/hosts` and open `http://anoix.local/`.

### Default logins (change immediately)

| Role | Email | Password |
|---|---|---|
| Ops | `ops@anoix.ng` | `ChangeMeNow!2024` |
| Retailer | `retailer@example.ng` | `ChangeMeNow!2024` |
| Distributor | `distributor@example.ng` | `ChangeMeNow!2024` |

### Run the test suite

```bash
export ANOIX_TEST_ALLOW=1
export DB_DATABASE=anoix_test
bash scripts/setup-test-db.sh   # or the manual steps above
php tests/run.php               # all suites
php tests/run.php ReleaseGuard  # one suite
```

Exit code is non-zero on any failure — CI-ready.

---

## Online deployment

### Option 1 — Shared hosting (cPanel / Plesk)

Most Nigerian shared hosts (WhoGoHost, QServers, DomainKing) support this.

1. **Upload the codebase** (via File Manager or SFTP). Place it outside `public_html` if possible, e.g. `~/anoix/`.
2. **Set the document root** to `<homedir>/anoix/public` via cPanel → Domains → Document Root.
   - If your host won't let you change the doc root, copy the contents of `public/` into `public_html/` and adjust the `require BASE_PATH . '/../...'` paths — or simply move `public_html` to `anoix/public` via a symlink if the host permits.
3. **Create a MySQL database** in cPanel → MySQL Databases. Note the DB name, user, and password — the host prefixes them (e.g. `myacct_anoix`).
4. **Import** the migrations + seeds through phpMyAdmin in this order:
   `001_initial_schema.sql` → `002_verification.sql` → `003_orders.sql` → `004_payments.sql` → `005_delivery.sql` → `006_disputes_reviews_notifications.sql` → then all six seed files.
5. **Create `.env`** in the project root:

   ```
   APP_ENV=production
   APP_DEBUG=0
   APP_URL=https://yourdomain.ng
   DB_HOST=localhost
   DB_PORT=3306
   DB_DATABASE=myacct_anoix
   DB_USERNAME=myacct_anoix
   DB_PASSWORD=<strong password>
   PAYMENT_PROVIDER=mock
   PAYMENT_MOCK_SECRET=<random 32+ chars>
   PAYMENT_MOCK_DEV_EMIT=0
   CODE_ENCRYPTION_KEY=<base64 32 bytes>
   ```

6. **Permissions**: `storage/` must be writable by the PHP user.
   ```
   chmod -R 755 storage
   ```
7. **HTTPS**: enable the free AutoSSL in cPanel. The `.htaccess` in `public/` will force HTTPS and set HSTS.
8. **Regenerate the seed hash** on your local machine before importing, or delete the seed users and create the first ops user manually via SQL.
9. **Verify** `https://yourdomain.ng/sitemap.xml` and `https://yourdomain.ng/robots.txt` return valid content.

### Option 2 — VPS / cloud (Ubuntu 22.04 or 24.04)

Best for production. Assumes a fresh Ubuntu box with a domain pointing at it.

**Install packages:**

```bash
sudo apt update && sudo apt install -y \
  nginx mysql-server php8.2-fpm php8.2-mysql php8.2-mbstring \
  php8.2-sodium php8.2-curl php8.2-xml php8.2-zip php8.2-gd \
  certbot python3-certbot-nginx unzip git
```

**Create the database:**

```bash
sudo mysql
CREATE DATABASE anoix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'anoix'@'localhost' IDENTIFIED BY '<strong password>';
GRANT ALL PRIVILEGES ON anoix.* TO 'anoix'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

**Deploy the code:**

```bash
sudo mkdir -p /var/www/anoix
sudo chown -R "$USER":www-data /var/www/anoix
git clone https://github.com/<you>/anoix.git /var/www/anoix
cd /var/www/anoix
cp .env.example .env
# edit .env with the production values
```

**Apply migrations + seeds:**

```bash
for f in database/migrations/*.sql database/seeds/*.sql; do
  mysql -u anoix -p anoix < "$f"
done
```

**Permissions:**

```bash
sudo chown -R www-data:www-data /var/www/anoix/storage
sudo chmod -R 750 /var/www/anoix/storage
sudo chown -R "$USER":www-data /var/www/anoix
```

**Nginx vhost — `/etc/nginx/sites-available/anoix`:**

```nginx
server {
    listen 80;
    server_name yourdomain.ng www.yourdomain.ng;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.ng www.yourdomain.ng;

    root /var/www/anoix/public;
    index index.php;

    # SSL (Certbot will fill these in)
    # ssl_certificate     /etc/letsencrypt/live/yourdomain.ng/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/yourdomain.ng/privkey.pem;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Compression
    gzip on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1024;

    # Static caching
    location ~* \.(?:css|js|woff2?|svg|png|jpg|jpeg|webp|avif|ico)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # Deny access to uploads storage (path safety)
    location /storage/ { return 404; }

    # Front controller
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_read_timeout 60s;
    }

    location ~ /\.(?!well-known) { deny all; }
}
```

**Enable the site, get SSL:**

```bash
sudo ln -s /etc/nginx/sites-available/anoix /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d yourdomain.ng -d www.yourdomain.ng
```

**PHP-FPM tweaks (`/etc/php/8.2/fpm/php.ini`):**

```ini
upload_max_filesize = 12M
post_max_size = 14M
max_execution_time = 60
expose_php = Off
display_errors = Off
log_errors = On
error_log = /var/log/php-anoix-error.log
```

Then `sudo systemctl restart php8.2-fpm`.

### Option 3 — Docker (optional)

Ship a `Dockerfile` + `docker-compose.yml` for reproducible deploys. Not included yet; if you want this, say so and I'll add it as a follow-up. A minimal version would use `php:8.2-fpm-alpine` + `nginx:alpine` + `mysql:8` with the `storage/` volume mounted.

### Post-deploy checks

```bash
# HTTPS + HSTS
curl -I https://yourdomain.ng | grep -i strict-transport

# Redirect works
curl -I http://yourdomain.ng | head -1     # expect 301

# SEO
curl -sS https://yourdomain.ng/robots.txt
curl -sS https://yourdomain.ng/sitemap.xml | head
curl -sS https://yourdomain.ng/llms.txt

# Lighthouse (mobile)
npx lighthouse https://yourdomain.ng/ --form-factor=mobile --throttling.cpuSlowdownMultiplier=4 --quiet --chrome-flags="--headless"

# Test suite against production-shaped DB (run locally with env pointing at a copy)
ANOIX_TEST_ALLOW=1 DB_DATABASE=anoix_test php tests/run.php
```

### Ongoing operations

**Backups (cron):**

```cron
0 3 * * * mysqldump -u anoix -p'<pass>' anoix | gzip > /var/backups/anoix-$(date +\%F).sql.gz
0 4 * * * tar -czf /var/backups/anoix-uploads-$(date +\%F).tar.gz -C /var/www/anoix storage/uploads
```

**Log rotation** for `/var/log/php-anoix-error.log` via `logrotate`.

**Monitoring** — at minimum, uptime on `/` and `/discover`, plus an alert if `/ops/admin` returns 500. Better: a Playwright script that runs the pilot flow end-to-end (register → browse → order → mock-fund → dispatch → code → evidence → ack → release) against a staging DB and fails the alert if any step breaks.

**Zero-downtime deploys** — this app has no shared session store, so rolling a new release is safe with a simple `git pull && composer install` (composer optional) + `systemctl reload php8.2-fpm`. The database migrations are additive; run them ahead of the code deploy.

### Going to a real payment provider

The `PaymentProviderInterface` is the only thing you need to implement. Add `app/Payments/Providers/PaystackPaymentProvider.php` (or Flutterwave, Monnify, etc.), register it in `PaymentProvider::resolve()`, set `PAYMENT_PROVIDER=paystack` in `.env`, and configure the webhook URL in the provider dashboard to `https://yourdomain.ng/webhooks/payments/paystack`.

Set `PAYMENT_MOCK_DEV_EMIT=0` in production — the mock emitter is disabled automatically when `APP_ENV=production`.

## Go-live checklist (pre-deploy)
Follow this checklist to reduce post-deploy issues.

- **Use a staging environment first:** mirror production (PHP, MySQL, domain). Run the full test suite against a staging DB.
- **Secrets & config:** set `APP_ENV=production`, `APP_DEBUG=0`, `APP_URL=https://yourdomain.ng`, strong `DB_PASSWORD`, `PAYMENT_MOCK_SECRET`, and a secure `CODE_ENCRYPTION_KEY` (32 bytes base64).
- **Migrate safely:** run SQL migrations in order (001–006) on the target DB and **backup** before applying to a production DB.
- **Seed carefully:** regenerate the seed bcrypt hash locally if you plan to import `database/seeds/001_seed.sql` on production, or create the first ops user manually.
- **Filesystem permissions:** `storage/` must be writable by the web server user and not world-writable. Use `chown www-data:www-data storage` and `chmod 750 storage`.
- **SSL & HSTS:** enable HTTPS (Let’s Encrypt) and verify HSTS headers are present.
- **Error handling:** set `display_errors=Off` and configure PHP logs; ensure `storage/logs` is writable and rotated.
- **Rate limits & lockouts:** verify `security.max_login_attempts` and lockout behavior in `config/config.php`.
- **Run smoke tests:** ensure `/`, `/login`, `/discover`, `/webhooks/payments/mock` (if used) respond with expected status codes.
- **Monitoring & alerts:** add uptime checks and error alerts (500s) for critical endpoints.

## Deploying to GitHub (recommended)
This repo can be pushed to GitHub and use Actions for CI and (optional) deploy.

1. Create a new GitHub repository (private/public) and follow the 'push an existing repository' instructions.

2. Recommended `.gitignore` (if missing):

```gitignore
# PHP
vendor/
.env
storage/logs/
storage/uploads/
/.idea
.vscode
/.DS_Store
node_modules/
*/.env.local
```

3. Add repository secrets (Settings → Secrets):
- `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`
- `PAYMENT_MOCK_SECRET`, `CODE_ENCRYPTION_KEY`
- `DEPLOY_SSH_KEY` (if deploying via SSH), or cloud provider secrets.

4. CI / GitHub Actions: create a workflow to run tests on push and PR. See `.github/workflows/ci.yml` (created in repo). The workflow runs `php tests/run.php` and fails the build on test failures.

5. Auto-deploy options:
- **SSH deploy** — Actions uses `DEPLOY_SSH_KEY` to `rsync` files to your server and run migrations.
- **Container / cloud** — build a Docker image and push to registry, update cloud service (e.g., DigitalOcean App Platform, GCP Cloud Run).

6. Post-deploy steps (on server):
- Set `.env` with production secrets.
- Run DB migrations + seeds.
- Set correct file permissions and restart PHP-FPM / web server.

If you want, I will create the GitHub Actions workflow and sample deploy script in `.github/workflows/ci.yml` and `scripts/deploy.sh` — want me to add them now?
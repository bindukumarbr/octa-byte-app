# ECS Deployment Challenges & Troubleshooting Report

During the deployment of the backend ECS service, several interrelated challenges were encountered. This document outlines the root causes and the solutions implemented for each issue.

## 1. Secrets Manager IAM Policy Attachment
**The Challenge:** The ECS backend task was failing to start with a `ResourceInitializationError`. The error indicated `AccessDeniedException` when trying to retrieve the RDS database credentials from AWS Secrets Manager. 
**The Cause:** The Terraform ECS module was not automatically attaching a `secretsmanager:GetSecretValue` inline policy to the Task Execution Role because the `task_exec_secret_arns` variable was missing from the service definition block in `main.tf`.
**The Solution:** The `task_exec_secret_arns` array was explicitly injected into the `backend` service definition in `main.tf` to ensure Terraform generated the correct IAM policy.

## 2. The Secrets Manager Wildcard "Gotcha"
**The Challenge:** Even after injecting the ARN into the configuration, the `AccessDeniedException` persisted.
**The Suspected Cause (not proven):** Secrets Manager appends a random 6-character suffix (e.g., `-eq2ug9`) to every secret ARN, and the working theory at the time was that the IAM policy was matching an ARN without that suffix. In hindsight this is doubtful: the RDS module's `db_instance_master_user_secret_arn` output is the secret's real ARN, which already includes the suffix, so the permission added in entry 1 was probably what actually fixed it.
**The Solution:** A trailing wildcard (`*`) was added to the ARN in the IAM policy, and it was kept as a defensive, low-risk safety net:
```hcl
task_exec_secret_arns = ["${module.db.db_instance_master_user_secret_arn}*"]
```
**Honest status:** The wildcard has not been re-tested without. The way to prove it is to remove the `*` on the next apply and check that the backend task still starts. If asked, describe it as "defensive; the root fix was granting the permission".

## 3. Environment Variable Name Mismatch (Crash Loop)
**The Challenge:** Once the IAM permissions were fixed, the task successfully pulled the secret but then immediately crashed with Exit Code 1.
**The Cause:** Checking the CloudWatch Logs (`/aws/ecs/backend/backend`) revealed the error: `Missing required environment variables: DB_PASSWORD`. The Terraform `secrets` block was injecting the password under the name `DB_PASS`, but the application's `env.js` file strictly required `DB_PASSWORD`.
**The Solution:** The `name` field in the `secrets` block of `main.tf` was updated to correctly map to `DB_PASSWORD`.

## 4. Terraform vs CI/CD State Drift
**The Challenge:** After pushing the `DB_PASSWORD` fix to GitHub, the pipeline ran and updated the image, but the task still crashed.
**The Cause:** There was a race condition between the local Terraform apply and the GitHub Actions pipeline:
1. The GitHub Actions pipeline ran first. It pulled the *old* task definition from AWS (which still had the broken `DB_PASS`), injected the real Docker image, and deployed it.
2. The `terraform apply` command was then run locally. This pushed the correct `DB_PASSWORD` fix to AWS, but it also overwrote the Docker image back to the placeholder `node:18-alpine` defined in `main.tf`.
**The Solution:** An empty git commit (`git commit --allow-empty`) was executed to trigger the GitHub Actions pipeline one more time. This allowed the pipeline to pull the newly fixed `DB_PASSWORD` task definition from AWS and inject the real backend Docker image into it, completing the deployment.

## 5. Nginx Proxy Pass Crashing Frontend in ECS
**The Challenge:** The frontend Nginx container crashed immediately on startup with `[emerg] host not found in upstream "backend"`.
**The Cause:** The `nginx.conf` contained a `proxy_pass http://backend:4000/` block. This works in local docker-compose environments where containers share a network namespace, but fails in ECS Fargate awsvpc networking where tasks do not share a service discovery DNS named `backend`.
**The Solution:** The `location /api/` proxy block was removed entirely. The ALB listener already uses path-based routing to forward `/api/*` directly to the backend target group, making the Nginx proxy redundant and conflicting.

## 6. Read-Only Root Filesystem Causing Nginx Crash
**The Challenge:** After fixing the proxy issue, the frontend container crashed again with `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`.
**The Cause:** The `terraform-aws-modules/ecs/aws` module enforces `readonly_root_filesystem = true` by default as a security best practice. While Node.js (backend) tolerates this, Nginx inherently requires write access to `/var/cache/nginx` and `/var/run` to start.
**The Solution (what was actually done):** `readonlyRootFilesystem = false` was set on the containers, so Nginx can write its cache and PID files. This is a deliberate, documented trade-off, not a full fix: the whole root filesystem is now writable.
**The proper fix (not implemented yet):** Restore read-only and add `tmpfs` mounts, via `linuxParameters.tmpfs`, for only `/var/cache/nginx` and `/var/run`. Fargate supports `tmpfs` since January 2026 (older AWS pages still say it does not). It needs a test deploy, because the Nginx image's entrypoint may also write elsewhere.

## 7. 404 "Cannot GET /api/transaction"
**The Challenge:** After the frontend and backend successfully booted, the frontend received a 404 error ("Cannot GET /api/transaction") when fetching data from the backend.
**The Cause:** The ALB path routing rule was configured to forward all `/api/*` traffic to the backend target group. The ALB does not strip the `/api/` prefix. However, the Node.js Express backend routes were strictly defined as `/transaction`, rather than `/api/transaction`. As a result, when the ALB sent a request to `/api/transaction`, Express could not find a matching route.
**The Solution:** The Express routes in both `index.js` and `app.js` were updated to prepend `/api` to all API routes (e.g. `app.post('/api/transaction')`). The backend unit tests were also updated to test the new `/api/transaction` routes.

## 8. 500 "no pg_hba.conf entry for host, no encryption"
**The Challenge:** After fixing the API routes, the backend returned a 500 Internal Server Error when posting a transaction. The CloudWatch logs revealed `[error] GET /api/transaction: error: no pg_hba.conf entry for host "10.0.2.182", user "dbadmin", database "octadb", no encryption`.
**The Cause:** The `pg` Node.js client was attempting to connect to the AWS RDS PostgreSQL database without SSL (which works fine in local Docker environments). However, AWS RDS enforces SSL-encrypted connections by default. 
**The Solution:** `ssl: { rejectUnauthorized: false }` was added to the Postgres pool configuration in `backend/db.js` to allow connecting to AWS RDS over SSL.

## 9. 500 "relation 'transactions' does not exist"
**The Challenge:** After enabling SSL, the backend continued to return a 500 Internal Server Error when posting a transaction. The logs showed `[error] GET /api/transaction: error: relation "transactions" does not exist`.
**The Cause:** While the AWS RDS database instance had been created successfully by Terraform, the actual `transactions` table schema had never been executed. The codebase contained a `schema.sql` file, but lacked an automated database migration or initialization script to apply it to the production database.
**The Solution:** `backend/index.js` was modified to automatically read and execute `schema.sql` (using `CREATE TABLE IF NOT EXISTS`) against the database pool on application startup before the Express server begins listening for requests.

## 10. 404 "Cannot DELETE /api/transaction/2"
**The Challenge:** When trying to delete a specific transaction from the frontend UI, the backend returned a 404 `Cannot DELETE /api/transaction/2`.
**The Cause:** The Express route for deleting (and fetching) by ID was literally defined as `app.delete('/api/transaction/id')` instead of using an Express path parameter like `/:id`. Because of this, it only matched the literal string "id" in the URL, not an actual numeric ID like "2". Furthermore, the backend validation middleware (`validateIdParam`) was mistakenly looking for the ID in `req.body.id` rather than `req.params.id`.
**The Solution:** The routes in `app.js` and `index.js` were updated to use `/:id` (e.g., `app.delete('/api/transaction/:id')`) and the route handlers and validation middleware were updated to extract the ID from `req.params.id`.

## 11. Tests Validated a Different Codepath Than What Was Deployed
**The Challenge:** While auditing the codebase before an interview, `index.js` and `app.js` turned out to be two independently hand-maintained copies of the same Express app (middleware, routes, error handler) instead of one requiring the other. `package.json`'s `start` script and the `Dockerfile` both run `node index.js` in production, but `api.test.js` imports `app.js`. The two had already drifted: `index.js`'s `/health` handler returned `res.json('This is the health check')` (a bare string), while `app.js`'s returned `res.json({ status: 'ok' })` — and the test asserts `res.body.status === "ok"`, which only ever exercised `app.js`'s version. A green test suite was not proof that the deployed `/health` route behaved as tested.
**The Cause:** At some point the two files were copy-pasted apart (likely when `app.js` was split out to make the app testable) and then edited independently, with no single source of truth.
**The Solution:** `index.js` was reduced to startup-only concerns (env validation, schema init via the IIFE, `app.listen()`, graceful shutdown) and now does `const app = require('./app')` instead of redefining every route. `app.js` is the single definition of the Express app; the test suite now genuinely tests the exact object that `node index.js` serves in production.
**Interview angle:** ALB health checks only look at the HTTP status code, so this never caused a production incident — but it's a good example of catching a test-validity gap by actually reading and running the code rather than trusting that "tests pass" means "tests prove the right thing."

## 12. Security Group Egress Rule Nested Inside `ingress_rules` (caught by reviewing the diff)
**The Challenge:** While adding explanatory comments to `main.tf`, the ECS security group's catch-all egress rule (`ip_protocol = "-1"`, `cidr_ipv4 = "0.0.0.0/0"`) ended up nested as an extra entry inside the `ingress_rules = { ... }` map instead of its own `egress_rules` block. The `terraform-aws-modules/security-group/aws` module creates a rule's direction (ingress vs egress) based on which variable it was passed into, not from the rule's name or contents — so this silently became an **inbound** rule allowing all protocols from the entire internet into the ECS security group, undermining the three-tier "defense in depth" story the rest of the infrastructure is built around.
**The Cause:** A copy/paste or reformatting slip while restructuring the module block to add comments — the rule kept its old key name (`egress_all`) but landed under the wrong map.
**The Solution:** Moved the rule back into its own `egress_rules = { egress_all = { ... } }` block, separate from `ingress_rules`. It was found by reading the diff against the committed version; `terraform validate` passes either way, because the rule is valid HCL in the wrong place.
**Also caught in the same pass:** `data.aws_region.current.name` was using an AWS provider v6 attribute that is now deprecated in favor of `.region`, fixed so `terraform validate` runs clean. (The ALB module version drift that was also found here turned out to be a much bigger problem. See entry 16.)
**Interview angle:** This is a good real example of "trust but verify" — comments and docs can drift from what the code actually does; reviewing your own diff (and reading the module source) is how you catch it before an interviewer does. Entry 16 shows the limit of `terraform validate`.

## 13. Dashboard Log Widget Pointed at an Empty Log Group
**The Challenge:** The "Backend Application Logs" widget on the application dashboard would have shown nothing, and three CloudWatch log groups in `monitoring.tf` held no data.
**The Cause:** `monitoring.tf` declared its own log groups (`/ecs/octa-byte-prod/frontend`, `.../backend`, and an ALB access one), but the ECS module creates its own group for each container, named `/aws/ecs/<service>/<container>` (the `/aws/ecs/backend/backend` path seen in entry 3). The containers wrote there, and the widget queried the hand-made empty one. The ALB group could never fill at all: ALB access logs can only go to S3, and `access_logs` was not enabled. The module's default retention (14 days) also differed from the 30 days the comments claimed.
**The Solution:** Removed the three unused log groups, set `cloudwatch_log_group_retention_in_days = 30` on each container definition, and pointed the widget at the module's group by reference (`module.ecs.services["backend"].container_definitions["backend"].cloudwatch_log_group_name`), so the name can't drift. Confirmed in `terraform plan`.

## 14. Vite Dev Proxy Still Stripped `/api`
**The Challenge:** Local development was broken even though production worked: every API call from `npm run dev` returned 404.
**The Cause:** After entry 7, the backend routes start with `/api`, but `vite.config.js` still had a `rewrite` that removed `/api` before forwarding, a leftover from when a proxy stripped the prefix. The backend received `/transaction`, which has no route.
**The Solution:** Removed the `rewrite` so the dev proxy forwards the path unchanged. Verified by running the real Express app and Vite dev server together: through the proxy, GET/POST/DELETE returned 200/201/200 (and 400 for bad input), while the old stripped path returned 404. `db.js` also gained a `DB_SSL=false` opt-out (default stays on) because a plain local Postgres has no SSL.

## 15. One Shared Security Group Let the Frontend Reach the Database
**The Challenge:** The README said only the backend could reach RDS, but the frontend tasks could too.
**The Cause:** Both ECS services used a single `ecs_sg`, and the RDS security group trusted that group, so the static Nginx containers inherited database access.
**The Solution:** Split it into `ecs_frontend_sg` (ingress 80 from the ALB) and `ecs_backend_sg` (ingress 4000 from the ALB), and made RDS trust only the backend group. Confirmed in `terraform plan`: the RDS rule `postgres_from_backend` references the backend group alone.

## 16. ALB Module Pin Loosened to v9: `validate` Passed, `plan` Failed
**The Challenge:** `terraform apply` would have failed. The ALB module version had been changed from the deployed `10.5.1` to `~> 9.0` while comments were being added.
**The Cause:** The listener-rule syntax in `main.tf` (`actions = [{ forward = {...} }]`) only exists from module v10; v9 expects `actions = [{ type = "forward", ... }]`. `terraform validate` passed because the module's inputs are loosely typed, so the mismatch only appeared at `terraform plan` with `Insufficient action blocks`.
**The Solution:** Restored `version = "10.5.1"` with a comment explaining why it is pinned, and re-ran `terraform plan` (83 resources to add, no errors).
**Interview angle:** `terraform validate` checks syntax, not whether a module accepts your values. Run `terraform plan` before trusting a configuration. (An earlier note in this file claimed the v9 pin was fine because `validate` passed. That was wrong, which is exactly this lesson.)

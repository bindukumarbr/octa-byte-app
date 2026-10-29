# Interview Prep — Study Order

## Files in this directory

| File | What it is |
| --- | --- |
| `interview_script.md` | 30-minute spoken walkthrough — architecture decisions, alternatives, trade-offs, cross-questions |
| `code_demo_script.md` | File-by-file code demo — what to open, what to say, what interviewers ask after seeing each file |
| `concepts_deep_dive.md` | Deeper explanations of specific mechanisms (Terraform state/locking, `cidrsubnet()`, `slice()`, `jsonencode()`) in plain language |
| `challenges_faced.md` | Troubleshooting report — every real production bug hit during the build and how it was resolved (16 entries) |
| `mock_qa.md` | Full mock-interview question bank with humanised model answers, organized by topic, incl. one Q&A per `challenges_faced.md` entry |
| `terraform_access_guide.md` | **Local only, deliberately not published** (it records account-specific security details; the repo is public). How Terraform itself gets AWS access: every option with pros/cons, what this project actually uses (verified against your account), the honest weak points, and an upgrade path |
| `general_topics_checklist.md` | **Not project-specific** — the broader DevOps/Cloud/SRE/Junior-Architect topic map, with priority tags and notes on where this project already gives you a real story vs where it's a pure-knowledge gap |

---

## Study Order (75 minutes total)

### Round 1 — Read the code comments (30 min)

Go through each file top to bottom, just reading the comments. Do not memorise yet — just understand the reasoning.

| Step | File | What to focus on |
| --- | --- | --- |
| 1 | `terraform/environments/prod/backend.tf` | Why remote state, why `use_lockfile` beats DynamoDB |
| 2 | `terraform/environments/prod/versions.tf` | Why pin versions, what `~>` means |
| 3 | `terraform/environments/prod/variables.tf` | Why `db_username` is a variable but `db_password` is NOT |
| 4 | `terraform/environments/prod/main.tf` | Read in order: VPC -> SG -> ALB -> RDS -> ECS -> OIDC |
| 5 | `terraform/environments/prod/outputs.tf` | How Terraform bridges to the CI/CD pipeline |
| 6 | `terraform/environments/prod/monitoring.tf` | Why CloudWatch, what each alarm watches, why two dashboards |
| 7 | `.github/workflows/deploy.yml` | Read job by job: test -> build -> deploy |
| 8 | `backend/index.js` | The IIFE startup block — most important Node.js explanation |
| 9 | `backend/db.js` | SSL enforcement and why env vars not hardcoded |
| 10 | `backend/__tests__/api.test.js` | Why everything is mocked, unit vs integration distinction |

---

### Round 2 — Cover and recall (30 min)

Go back to each file. Cover the comments (collapse or scroll past them). For each important line, ask yourself out loud:

- "Why is this line here?"
- "What would break if I removed it?"
- "What was the alternative and why was it rejected?"

Lines that matter most to practice:

  use_lockfile = true                          -> backend.tf
  manage_master_user_password = true           -> main.tf
  task_exec_secret_arns = ["...${arn}*"]       -> main.tf (the permission; the * is precautionary)
  referenced_security_group_id =               -> main.tf (SG chaining)
  process.exit(1)                              -> index.js (fail-fast)
  id-token: write                              -> deploy.yml (OIDC)
  echo "tag=${{ github.sha }}"                 -> deploy.yml (immutable tags)
  ssl: { rejectUnauthorized: false }           -> db.js (RDS SSL)

---

### Round 3 — Answer cross-questions cold (15 min)

Open `interview_script.md` and go to the Quick Reference Cheat Sheet table at the bottom.

Cover the right column (answers). Read each question out loud and answer before looking.

If you hesitate on any answer, go back to the comment in that specific file.

---

## Key talking points to have completely natural (no notes needed)

These will come up in every technical interview — practice until automatic:

1. Why S3 native locking, not DynamoDB?
   Terraform 1.10+ feature. DynamoDB locking is a legacy pattern this version has moved past.

2. Why SG-to-SG references, not CIDR?
   Fargate ENIs get new IPs on every deploy. CIDR rules allow anything in that network range,
   not just the specific resource. SG references scope access to the exact resource group.

3. Why manage_master_user_password = true?
   Password never exists in code, state file, or CI logs.
   AWS generates and stores it in Secrets Manager entirely.

4. The Secrets Manager AccessDenied (and the wildcard).
   The real fix: the execution role had no GetSecretValue permission at all
   (task_exec_secret_arns). The trailing * on the ARN was added while debugging;
   the module's output ARN already includes AWS's 6-char suffix, so the * is
   probably unnecessary. Keep it as a defensive precaution, say so honestly,
   and offer to test removing it on the next apply.

5. Why OIDC, not stored AWS keys?
   OIDC tokens expire in minutes. Stored keys are a standing liability until manually rotated.

6. The IIFE in index.js.
   Schema runs before app.listen(). process.exit(1) on failure.
   Without it: race condition where ALB thinks container is healthy while DB layer is broken.

7. Why git SHA tag, not latest?
   Exact traceability to the commit. Instant rollback without rebuild —
   just force deploy the previous task definition revision.

8. The OIDC sub claim numeric IDs.
   GitHub uses numeric repo/owner IDs (not names) in the sub claim to prevent
   trust-policy hijacking on repo rename/recreate.
   Decoded the actual JWT from a failed run to discover the real format.

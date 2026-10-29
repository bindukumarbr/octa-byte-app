const { Pool } = require("pg");

// ============================================================
// INTERVIEW NOTE: This file creates the PostgreSQL connection pool.
// A pool keeps a set of open DB connections ready and reuses them,
// rather than opening and closing a new connection on every request.
// Opening a TCP connection to a database is expensive (~50-100ms).
// Pooling brings that cost to near zero for subsequent queries.
// ============================================================

const pool = new Pool({
  // WHY environment variables (not hardcoded values):
  // Hardcoding "host: 'mydb.abc123.us-east-1.rds.amazonaws.com'"
  // would mean the connection string is committed to git history
  // forever. Using env vars means the same Docker image runs locally
  // (pointing to a local DB) and in AWS (pointing to RDS) with zero
  // code changes — only the env vars differ.
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD, // injected from Secrets Manager by ECS at container startup
  database: process.env.DB_NAME,
  port: process.env.DB_PORT || 5432,

  // WHY ssl is required for AWS RDS:
  // AWS RDS enforces SSL-encrypted connections by default.
  // Without this option, the pg client sends an unencrypted handshake
  // and RDS rejects it with:
  //   "no pg_hba.conf entry for host, no encryption"
  // This was a real production failure we debugged via CloudWatch logs.
  //
  // WHY rejectUnauthorized: false (and the honest trade-off):
  // "true" would validate the RDS TLS certificate against a CA bundle,
  // which is the fully hardened approach. "false" means SSL encryption
  // is enforced (traffic is encrypted) but the certificate is not
  // validated — leaving a theoretical MITM vulnerability.
  // In an AWS private subnet with no public internet route on RDS,
  // the practical MITM risk is extremely low.
  // Production hardening: set rejectUnauthorized: true and provide
  //   ca: fs.readFileSync('rds-ca-bundle.pem')
  // using the AWS-published RDS CA certificate.
  //
  // CROSS-QUESTION: "Is rejectUnauthorized: false a security risk?"
  // Encrypted yes, certificate-validated no. Acceptable for a private
  // subnet; not acceptable in a compliance-regulated environment.
  //
  // DB_SSL=false is an explicit opt-out for LOCAL development only: a plain
  // Postgres container has no SSL, and the pg client errors out ("The server
  // does not support SSL connections") if SSL is requested. It is never set
  // in AWS, so production keeps SSL on by default.
  ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false },
});

module.exports = pool;

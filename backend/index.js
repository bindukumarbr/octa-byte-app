// ============================================================
// INTERVIEW NOTE: validateEnv() runs FIRST — before any require()
// that might need env vars. It checks that all required environment
// variables (DB_HOST, DB_USER, DB_PASSWORD, etc.) are present.
// If any are missing, it calls process.exit(1) immediately.
// WHY fail-fast here: starting the server without a DB host configured
// would mean every request fails with an opaque connection error.
// Better to crash loudly with a clear message at startup.
// ============================================================
const { validateEnv } = require('./env');
validateEnv();

const fs   = require('fs');
const path = require('path');
const pool = require('./db');
const app  = require('./app'); // Express app + all routes live in app.js — see that file

const port = process.env.PORT || 4000;

// ============================================================
// INTERVIEW NOTE — SCHEMA INITIALIZATION (key talking point):
//
// WHY the schema init runs here and not via a migration tool:
// AWS RDS provisions a completely blank database. Unlike local Docker
// which can run SQL init scripts via entrypoint hooks, there is no
// built-in RDS mechanism to apply a schema. A dedicated migration tool
// (Flyway, Liquibase) is the correct enterprise approach but requires
// either opening RDS to the internet (security risk) or a dedicated
// ECS migration task (heavy overhead for a single table).
// For this project: the backend itself applies the schema on startup.
//
// WHY an async IIFE (Immediately Invoked Function Expression):
// We need to await the database query before calling app.listen().
// Top-level await is not available in CommonJS modules (require-based).
// Wrapping everything in (async () => { ... })() is the standard pattern
// to use async/await at the top level of a CommonJS module.
//
// WHY schema init runs BEFORE app.listen() (critical ordering):
// If app.listen() ran first, Express would immediately start accepting
// TCP connections. An early request hitting /api/transaction before
// pool.query(schemaSql) completes would find "relation transactions
// does not exist" — a race condition. The IIFE guarantees the table
// exists before the server accepts any traffic.
//
// WHY process.exit(1) on failure (fail-fast philosophy):
// If we only console.error and continue, Express starts serving requests
// against a DB layer that silently does not work. The ALB health check
// calls /health which returns 200 (Express is running fine), so the ALB
// keeps routing real user traffic to a broken container. Calling
// process.exit(1) crashes the container instantly — ECS marks it
// unhealthy, the ALB stops routing to it, and the deployment fails
// visibly rather than silently serving 500 errors.
//
// CROSS-QUESTION: "What is CREATE TABLE IF NOT EXISTS doing?"
// It makes initialization idempotent. First boot: creates the table.
// Every subsequent boot: the table exists, IF NOT EXISTS skips creation.
// This means we never accidentally drop and recreate a table with live data.
// ============================================================
(async () => {
  try {
    const schemaSql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    await pool.query(schemaSql);
    console.log('Database schema initialized');

    // app.listen() is called ONLY after schema is confirmed to exist.
    const server = app.listen(port, () => {
      console.log(`Backend listening on port ${port}`);
    });

    // Graceful shutdown: when ECS sends SIGTERM (during a rolling deploy
    // or scale-in event), we stop accepting new connections, wait for
    // in-flight requests to complete, then close the DB pool cleanly.
    // Without this, killing the process mid-request causes connection
    // resets and potential data corruption on open transactions.
    // The handlers are registered below, only after `server` exists, so
    // there is no "server not started yet" case to handle here.
    function shutdown(signal) {
      console.log(`${signal} received, shutting down gracefully`);
      server.close(async () => {
        await pool.end();
        process.exit(0);
      });
    }

    process.on('SIGTERM', () => shutdown('SIGTERM')); // ECS sends this on task stop
    process.on('SIGINT',  () => shutdown('SIGINT'));  // Ctrl+C in local dev

  } catch (err) {
    // Fail fast — do not start the server with a broken database layer.
    console.error('CRITICAL: Failed to initialize database schema:', err);
    process.exit(1);
  }
})();

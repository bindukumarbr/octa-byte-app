// app.js — Express app definition (separate from server startup for testability)
//
// WHY this file exists separately from index.js:
// index.js owns startup concerns (env validation, DB schema init, app.listen,
// graceful shutdown) — things that touch real infrastructure and should only
// run once, when the process actually boots.
// app.js owns only the Express app itself: middleware, routes, error handling.
// index.js requires this file and calls app.listen() on it; the test suite
// requires this file directly and drives it with Supertest, without ever
// touching the DB or starting a real server. Same object, two entry points.
const express = require("express");
const cors = require("cors");
const {
  validateTransactionBody,
  validateIdParam,
} = require("./middleware/validation");
const { errorHandler } = require("./middleware/errorHandler");
const transactionService = require("./TransactionService");

const app = express();

// The frontend only ever sends JSON. express.json() is the same function the
// separate body-parser package exports, so no extra dependency is needed.
app.use(express.json());
app.use(cors());

// Request logger middleware — logs method, path, status, and duration.
// These lines appear in CloudWatch Logs, which is how we debugged
// the ALB routing issues and the SSL connection failures in AWS.
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    console.log(
      `${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`,
    );
  });
  next();
});

// INTERVIEW NOTE: Why /health and not just using GET /api/transaction:
// The ALB health check needs a lightweight, fast endpoint with no
// database dependency. If the health check hit a real API route,
// a DB timeout would make the container look unhealthy even if Express
// is running fine. /health returns 200 immediately regardless of DB state.
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// INTERVIEW NOTE: WHY all routes are prefixed /api/ (not /transaction):
// Originally the backend routes had no prefix, because a proxy in front of
// it stripped /api (Nginx's proxy_pass, and the Vite dev proxy locally).
// In AWS ECS with awsvpc networking, Nginx's "upstream backend" host does
// not resolve, so the Nginx proxy was removed and the ALB now routes
// /api/* straight to the backend target group.
// Nothing strips the prefix any more: the ALB forwards the path unchanged,
// and the Vite dev proxy (vite.config.js) also forwards it unchanged.
// So the Express routes must include /api/ to match what actually arrives.
// This was a live production bug: 404 on every API call until fixed.
app.post(
  "/api/transaction",
  validateTransactionBody,
  async (req, res, next) => {
    try {
      const transaction = await transactionService.addTransaction(
        req.body.amount,
        req.body.desc,
      );
      res
        .status(201)
        .json({ message: "added transaction successfully", transaction });
    } catch (err) {
      next(err);
    }
  },
);

app.get("/api/transaction", async (req, res, next) => {
  try {
    const result = await transactionService.getAllTransactions();
    res.status(200).json({ result });
  } catch (err) {
    next(err);
  }
});

app.delete("/api/transaction", async (req, res, next) => {
  try {
    await transactionService.deleteAllTransactions();
    res.status(200).json({ message: "delete function execution finished." });
  } catch (err) {
    next(err);
  }
});

// INTERVIEW NOTE: WHY :id as a path parameter (not /api/transaction/id literally):
// The original code had app.delete('/api/transaction/id') — the literal string "id".
// This only matched requests with the exact URL /api/transaction/id, not
// /api/transaction/1 or /api/transaction/42. Express path parameters use
// the colon syntax: /:id creates req.params.id populated from the URL segment.
app.delete("/api/transaction/:id", validateIdParam, async (req, res, next) => {
  try {
    await transactionService.deleteTransactionById(req.params.id);
    res
      .status(200)
      .json({ message: `transaction with id ${req.params.id} deleted` });
  } catch (err) {
    next(err);
  }
});

app.get("/api/transaction/:id", validateIdParam, async (req, res, next) => {
  try {
    const transaction = await transactionService.findTransactionById(
      req.params.id,
    );
    if (!transaction) {
      return res.status(404).json({ message: "transaction not found" });
    }
    res.status(200).json(transaction);
  } catch (err) {
    next(err);
  }
});

// Global error handler — catches any error passed to next(err) above.
app.use(errorHandler);

module.exports = app;

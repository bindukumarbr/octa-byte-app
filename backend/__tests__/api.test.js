// ============================================================
// INTERVIEW NOTE: This file uses Jest (test runner) + Supertest
// (HTTP assertion library). Supertest lets you make real HTTP
// requests to an Express app in-process, without starting a server.
// ============================================================
const request = require("supertest");

// WHY mock TransactionService (and nothing else):
// TransactionService contains the actual SQL queries. Mocking it means
// we control exactly what value gets "returned from the DB" per test,
// without needing real data. This isolates the Express routing and
// middleware layer from the data access layer.
// We are testing "does Express route correctly and return the right
// status codes?" — not "does the SQL query work?" (that would be
// a separate DB integration test).
//
// Because the whole service is replaced, the real db.js pool is never
// loaded, so it needs no mock of its own. Likewise env.js (which calls
// process.exit(1) when DB_* variables are missing) is only required by
// index.js, never by app.js, so it never runs under test either.
// This makes tests: fast (no network), reliable (no DB state),
// and runnable anywhere (no infrastructure dependency).
jest.mock("../TransactionService", () => ({
  addTransaction:        jest.fn(),
  getAllTransactions:     jest.fn(),
  deleteAllTransactions:  jest.fn(),
  deleteTransactionById:  jest.fn(),
  findTransactionById:    jest.fn(),
}));

// We import "app" (the Express instance), NOT "index.js" (which starts
// the server and touches the DB). This is why app.js and index.js are
// separated — index.js wires startup concerns (DB init, listen, shutdown)
// while app.js only defines the Express routes. Tests import app.js directly.
const app                = require("../app");
const transactionService = require("../TransactionService");

// ============================================================
// HEALTH CHECK
// ============================================================
describe("GET /health", () => {
  it("should return 200 and status ok", async () => {
    const res = await request(app).get("/health");
    // CROSS-QUESTION: "Why test /health separately?"
    // The ALB health check depends on this endpoint returning 200.
    // If a code change accidentally broke this route, the container
    // would be pulled from rotation and users would see 502s.
    // Having an explicit test for it prevents that regression.
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("ok");
  });
});

// ============================================================
// GET ALL TRANSACTIONS
// ============================================================
describe("GET /transaction", () => {
  it("should return 200 with list of transactions", async () => {
    // mockResolvedValue sets what getAllTransactions() returns for THIS test.
    // Next test gets a clean mock — no state leaks between tests.
    transactionService.getAllTransactions.mockResolvedValue([
      { id: 1, amount: 100, desc: "test" },
    ]);
    const res = await request(app).get("/api/transaction");
    expect(res.statusCode).toBe(200);
    expect(res.body.result).toHaveLength(1);
  });
});

// ============================================================
// POST (CREATE) TRANSACTION
// ============================================================
describe("POST /transaction", () => {
  it("should return 201 when body is valid", async () => {
    transactionService.addTransaction.mockResolvedValue({
      id: 1, amount: 50, desc: "lunch",
    });
    const res = await request(app)
      .post("/api/transaction")
      .send({ amount: 50, desc: "lunch" });
    expect(res.statusCode).toBe(201);
    expect(res.body.message).toBe("added transaction successfully");
  });

  // INTERVIEW NOTE: These two tests validate the INPUT VALIDATION MIDDLEWARE.
  // The validateTransactionBody middleware in validation.js should reject
  // requests missing required fields with a 400 before they reach the service.
  // Testing the failure cases is just as important as the happy path —
  // if a bad deploy broke the middleware, these tests would catch it.
  it("should return 400 when amount is missing", async () => {
    const res = await request(app).post("/api/transaction").send({ desc: "lunch" });
    expect(res.statusCode).toBe(400);
  });

  it("should return 400 when desc is missing", async () => {
    const res = await request(app).post("/api/transaction").send({ amount: 50 });
    expect(res.statusCode).toBe(400);
  });
});

// ============================================================
// DELETE ALL TRANSACTIONS
// ============================================================
describe("DELETE /transaction", () => {
  it("should return 200 when all transactions deleted", async () => {
    transactionService.deleteAllTransactions.mockResolvedValue();
    const res = await request(app).delete("/api/transaction");
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toBe("delete function execution finished.");
  });
});

// CROSS-QUESTION: "Are these unit tests or integration tests?"
// Technically integration tests — they test the full request/response
// cycle through Express routing, middleware, and service layer together.
// They are NOT end-to-end (no real DB, no real HTTP server port).
// A true unit test would test a single function in isolation.
// The next level of testing would be DB integration tests using
// a real (or in-memory) PostgreSQL instance, validating the actual SQL.

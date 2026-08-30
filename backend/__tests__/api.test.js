// Integration tests using Supertest
const request = require("supertest");

// Mock the DB pool so tests never need a real PostgreSQL connection
jest.mock("../db", () => ({
  query: jest.fn(),
  end: jest.fn(),
}));

// Mock the TransactionService to control return values per test
jest.mock("../TransactionService", () => ({
  addTransaction: jest.fn(),
  getAllTransactions: jest.fn(),
  deleteAllTransactions: jest.fn(),
  deleteTransactionById: jest.fn(),
  findTransactionById: jest.fn(),
}));

// Mock env validation so the app starts without real env vars
jest.mock("../env", () => ({
  validateEnv: jest.fn(),
}));

const app = require("../app");
const transactionService = require("../TransactionService");

// Health Check
describe("GET /health", () => {
  it("should return 200 and status ok", async () => {
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("ok");
  });
});

// GET /transaction
describe("GET /transaction", () => {
  it("should return 200 with list of transactions", async () => {
    transactionService.getAllTransactions.mockResolvedValue([
      { id: 1, amount: 100, desc: "test" },
    ]);
    const res = await request(app).get("/api/transaction");
    expect(res.statusCode).toBe(200);
    expect(res.body.result).toHaveLength(1);
  });
});

// POST /transaction
describe("POST /transaction", () => {
  it("should return 201 when body is valid", async () => {
    transactionService.addTransaction.mockResolvedValue({
      id: 1,
      amount: 50,
      desc: "lunch",
    });
    const res = await request(app)
      .post("/api/transaction")
      .send({ amount: 50, desc: "lunch" });
    expect(res.statusCode).toBe(201);
    expect(res.body.message).toBe("added transaction successfully");
  });

  it("should return 400 when amount is missing", async () => {
    const res = await request(app).post("/api/transaction").send({ desc: "lunch" });
    expect(res.statusCode).toBe(400);
  });

  it("should return 400 when desc is missing", async () => {
    const res = await request(app).post("/api/transaction").send({ amount: 50 });
    expect(res.statusCode).toBe(400);
  });
});

// DELETE /transaction
describe("DELETE /transaction", () => {
  it("should return 200 when all transactions deleted", async () => {
    transactionService.deleteAllTransactions.mockResolvedValue();
    const res = await request(app).delete("/api/transaction");
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toBe("delete function execution finished.");
  });
});


const pool = require("./db");

// create new record
async function addTransaction(amount, desc) {
  const result = await pool.query(
    "INSERT INTO transactions (amount, description) VALUES ($1, $2) RETURNING *",
    [amount, desc],
  );
  return result.rows[0];
}

// get everything
async function getAllTransactions() {
  const result = await pool.query(
    "SELECT * FROM transactions ORDER BY id DESC",
  );
  return result.rows;
}

async function findTransactionById(id) {
  const result = await pool.query("SELECT * FROM transactions WHERE id = $1", [
    id,
  ]);
  return result.rows[0];
}

// delete everything
async function deleteAllTransactions() {
  await pool.query("DELETE FROM transactions");
}

// delete single
async function deleteTransactionById(id) {
  await pool.query("DELETE FROM transactions WHERE id = $1", [id]);
}

module.exports = {
  addTransaction,
  getAllTransactions,
  findTransactionById,
  deleteAllTransactions,
  deleteTransactionById,
};

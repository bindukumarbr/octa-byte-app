const { validateEnv } = require('./env');
validateEnv();

const transactionService = require('./TransactionService');
const pool = require('./db');
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { validateTransactionBody, validateIdParam } = require('./middleware/validation');
const { errorHandler } = require('./middleware/errorHandler');

// setup express
const app = express();
const port = process.env.PORT || 4000;

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());
app.use(cors());

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    console.log(`${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json('This is the health check');
});

app.post('/api/transaction', validateTransactionBody, async (req, res, next) => {
  try {
    const transaction = await transactionService.addTransaction(req.body.amount, req.body.desc);
    res.status(201).json({ message: 'added transaction successfully', transaction });
  } catch (err) {
    next(err);
  }
});

app.get('/api/transaction', async (req, res, next) => {
  try {
    const result = await transactionService.getAllTransactions();
    res.status(200).json({ result });
  } catch (err) {
    next(err);
  }
});

app.delete('/api/transaction', async (req, res, next) => {
  try {
    await transactionService.deleteAllTransactions();
    res.status(200).json({ message: 'delete function execution finished.' });
  } catch (err) {
    next(err);
  }
});

app.delete('/api/transaction/id', validateIdParam, async (req, res, next) => {
  try {
    await transactionService.deleteTransactionById(req.body.id);
    res.status(200).json({ message: `transaction with id ${req.body.id} deleted` });
  } catch (err) {
    next(err);
  }
});

app.get('/api/transaction/id', validateIdParam, async (req, res, next) => {
  try {
    const transaction = await transactionService.findTransactionById(req.body.id);
    if (!transaction) {
      return res.status(404).json({ message: 'transaction not found' });
    }
    res.status(200).json(transaction);
  } catch (err) {
    next(err);
  }
});

app.use(errorHandler);

const server = // start server
app.listen(port, () => {
  console.log(`Backend listening on port ${port}`);
});

function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully`);
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));


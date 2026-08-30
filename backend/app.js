// app.js — Express app definition (separate from server startup for testability)
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { validateTransactionBody, validateIdParam } = require('./middleware/validation');
const { errorHandler } = require('./middleware/errorHandler');
const transactionService = require('./TransactionService');

const app = express();

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());
app.use(cors());

// request logger
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    console.log(`${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.post('/transaction', validateTransactionBody, async (req, res, next) => {
  try {
    const transaction = await transactionService.addTransaction(req.body.amount, req.body.desc);
    res.status(201).json({ message: 'added transaction successfully', transaction });
  } catch (err) {
    next(err);
  }
});

app.get('/transaction', async (req, res, next) => {
  try {
    const result = await transactionService.getAllTransactions();
    res.status(200).json({ result });
  } catch (err) {
    next(err);
  }
});

app.delete('/transaction', async (req, res, next) => {
  try {
    await transactionService.deleteAllTransactions();
    res.status(200).json({ message: 'delete function execution finished.' });
  } catch (err) {
    next(err);
  }
});

app.delete('/transaction/id', validateIdParam, async (req, res, next) => {
  try {
    await transactionService.deleteTransactionById(req.body.id);
    res.status(200).json({ message: `transaction with id ${req.body.id} deleted` });
  } catch (err) {
    next(err);
  }
});

app.get('/transaction/id', validateIdParam, async (req, res, next) => {
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

module.exports = app;

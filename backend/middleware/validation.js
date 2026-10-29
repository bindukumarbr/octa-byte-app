// validate incoming payload
function validateTransactionBody(req, res, next) {
  const { amount, desc } = req.body;

  // Number(null) is 0, so null needs its own check. A missing amount
  // (undefined) becomes NaN and is already caught by isNaN().
  if (amount === null || isNaN(Number(amount))) {
    return res.status(400).json({ message: 'amount must be a number' });
  }
  // typeof also rejects a missing desc (undefined/null), so no separate !desc check.
  if (typeof desc !== 'string' || desc.trim().length === 0) {
    return res.status(400).json({ message: 'desc must be a non-empty string' });
  }
  if (desc.length > 255) {
    return res.status(400).json({ message: 'desc must be 255 characters or fewer' });
  }

  next();
}

// Express's /:id route always supplies a non-empty string, so only the
// numeric check can ever fail here.
function validateIdParam(req, res, next) {
  const { id } = req.params;
  if (isNaN(Number(id))) {
    return res.status(400).json({ message: 'id must be a number' });
  }
  next();
}

module.exports = { validateTransactionBody, validateIdParam };

// validate incoming payload
function validateTransactionBody(req, res, next) {
  const { amount, desc } = req.body;

  if (amount === undefined || amount === null || isNaN(Number(amount))) {
    return res.status(400).json({ message: 'amount must be a number' });
  }
  if (!desc || typeof desc !== 'string' || desc.trim().length === 0) {
    return res.status(400).json({ message: 'desc must be a non-empty string' });
  }
  if (desc.length > 255) {
    return res.status(400).json({ message: 'desc must be 255 characters or fewer' });
  }

  next();
}

function validateIdParam(req, res, next) {
  const { id } = req.params;
  if (id === undefined || id === null || isNaN(Number(id))) {
    return res.status(400).json({ message: 'id must be a number' });
  }
  next();
}

module.exports = { validateTransactionBody, validateIdParam };


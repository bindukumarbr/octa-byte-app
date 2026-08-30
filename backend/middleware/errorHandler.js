// catch all errors so the app doesnt crash
function errorHandler(err, req, res, next) {
  console.error(`[error] ${req.method} ${req.path}:`, err);

  res.status(err.status || 500).json({
    message: 'Something went wrong. Please try again.',
  });
}

module.exports = { errorHandler };

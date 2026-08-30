CREATE TABLE IF NOT EXISTS transactions (
  id          SERIAL PRIMARY KEY,
  amount      DECIMAL(10,2) NOT NULL,
  description VARCHAR(255)  NOT NULL,
  created_at  TIMESTAMP DEFAULT NOW()
);

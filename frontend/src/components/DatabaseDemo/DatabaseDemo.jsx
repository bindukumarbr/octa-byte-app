import React, { useState, useEffect } from 'react';
import './DatabaseDemo.css';

export default function DatabaseDemo() {
  const [transactions, setTransactions] = useState([]);
  const [amount, setAmount] = useState('');
  const [desc, setDesc] = useState('');
  const [isLoading, setIsLoading] = useState(false);

    // load initial data on mount
  useEffect(() => {
    fetchTransactions();
  }, []);

  const fetchTransactions = async (retries = 3) => {
    try {
      const response = await fetch('/api/transaction');
      const data = await response.json();
      setTransactions(data.result || []);
    } catch (err) {
      if (retries > 0) {
        setTimeout(() => fetchTransactions(retries - 1), 1000);
      } else {
        console.error('Failed to fetch transactions:', err);
      }
    }
  };

    // handle form submit
  const handleAdd = async (e) => {
    e.preventDefault();
    if (!amount || !desc) return;
    
    setIsLoading(true);
    try {
      await fetch('/api/transaction', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ amount, desc })
      });
      setAmount('');
      setDesc('');
      await fetchTransactions();
    } catch (err) {
      console.error('Failed to add:', err);
    } finally {
      setIsLoading(false);
    }
  };

    // nuke everything
  const handleDeleteAll = async () => {
    if (!window.confirm('Are you sure you want to delete all transactions?')) return;
    
    try {
      await fetch('/api/transaction', { method: 'DELETE' });
      await fetchTransactions();
    } catch (err) {
      console.error('Failed to delete all:', err);
    }
  };

  const handleDeleteOne = async (id) => {
    try {
      await fetch(`/api/transaction/${id}`, { method: 'DELETE' });
      await fetchTransactions();
    } catch (err) {
      console.error(`Failed to delete transaction ${id}:`, err);
    }
  };

  return (
    <div className="db-demo-container">
      <h2 className="title">Transaction Database</h2>
      
      <div className="glass-card">
        <form className="transaction-form" onSubmit={handleAdd}>
          <div className="input-group">
            <input 
              type="number" 
              className="glass-input" 
              placeholder="Amount ($)" 
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              disabled={isLoading}
              required
            />
          </div>
          <div className="input-group">
            <input 
              type="text" 
              className="glass-input" 
              placeholder="Description" 
              value={desc}
              onChange={(e) => setDesc(e.target.value)}
              disabled={isLoading}
              required
            />
          </div>
          <button type="submit" className="btn btn-primary" disabled={isLoading}>
            {isLoading ? 'Adding...' : '+ Add Record'}
          </button>
        </form>
      </div>

      <div className="glass-card">
        <div className="header-flex">
          <h3>Recent Transactions</h3>
          {transactions.length > 0 && (
            <button className="btn btn-danger" onClick={handleDeleteAll}>
              Delete All
            </button>
          )}
        </div>
        
        <div className="table-container">
          <table className="glass-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Amount</th>
                <th>Description</th>
                <th style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {transactions.length === 0 ? (
                <tr>
                  <td colSpan="4" className="empty-state">
                    No transactions found. Add one above!
                  </td>
                </tr>
              ) : (
                transactions.map((t) => (
                  <tr key={t.id}>
                    <td>#{t.id}</td>
                    <td className="amount">${parseFloat(t.amount).toFixed(2)}</td>
                    <td>{t.description}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button 
                        className="btn btn-icon" 
                        onClick={() => handleDeleteOne(t.id)}
                        title="Delete"
                      >
                        ✕
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

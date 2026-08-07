import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';

function App() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    fetch(`${apiUrl}/mutations/`)
      .then(res => {
        if (!res.ok) throw new Error('Failed to fetch');
        return res.json();
      })
      .then(data => {
        setData(data);
        setLoading(false);
      })
      .catch(err => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      <h1>Parachute Forensics Dashboard</h1>
      <table border="1">
        <thead><tr><th>ID</th><th>File</th><th>Line</th><th>Status</th><th>Timestamp</th></tr></thead>
        <tbody>
          {data.map(m => (
            <tr key={m.id}>
              <td>{m.id}</td>
              <td>{m.file_path}</td>
              <td>{m.line_number}</td>
              <td>{m.status}</td>
              <td>{m.fixed_ts}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

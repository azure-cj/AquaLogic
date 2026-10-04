import App from '@/app/App';
import { AppProviders } from '@/app/providers';
import '@/styles/base.css';
import '@/styles/dark-theme.css';
import React from 'react';
import ReactDOM from 'react-dom/client';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AppProviders>
      {import.meta.env.VITE_SYNTHETIC_REVIEW === '1' && <div role="status" style={{ background: '#fff1c2', color: '#3d3100', padding: '8px 16px', fontWeight: 600, textAlign: 'center' }}>Synthetic review data · Local API · No live aquarium connection</div>}
      <App />
    </AppProviders>
  </React.StrictMode>,
);

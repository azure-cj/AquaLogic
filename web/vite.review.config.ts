import { defineConfig, mergeConfig } from 'vite';
import base from './vite.config';

const port = Number(process.env.AQUALOGIC_REVIEW_API_PORT);
if (!Number.isInteger(port) || port < 8800 || port > 8899) throw new Error('Review requires an isolated API port (8800–8899).');
export default mergeConfig(base, defineConfig({
  envDir: false,
  define: { 'import.meta.env.VITE_SYNTHETIC_REVIEW': JSON.stringify('1'), 'import.meta.env.VITE_API_BASE_URL': JSON.stringify('/api') },
  server: { host: '127.0.0.1', strictPort: true, allowedHosts: ['127.0.0.1'], proxy: { '/api': { target: `http://127.0.0.1:${port}`, changeOrigin: true, rewrite: (path: string) => path.replace(/^\/api/, '') } } },
}));

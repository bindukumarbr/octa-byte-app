import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // In dev, forward /api/* to the backend UNCHANGED. The backend routes
    // already start with /api (the ALB forwards the path as-is in AWS), so
    // the prefix must not be stripped here or every call would 404.
    proxy: {
      '/api': {
        target: 'http://localhost:4000',
        changeOrigin: true,
      },
    },
  },
});

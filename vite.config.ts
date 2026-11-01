// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Keep Vite's dependency crawl on the app module graph; the repository also
  // contains generated HTML under work/ and src-tauri/gen/.
  optimizeDeps: {
    entries: ['src/main.tsx'],
  },
  server: {
    port: 5173,
    strictPort: true,
    // Native build outputs and synthetic fixtures are not frontend inputs.
    // Watching them stalls Vite's HTTP responses on Windows after a build.
    watch: {
      ignored: ['**/src-tauri/target/**', '**/src-tauri/gen/**', '**/work/**'],
    },
  },
})

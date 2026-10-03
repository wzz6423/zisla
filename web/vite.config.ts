import { resolve } from 'node:path';
import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    rollupOptions: {
      // The showcase animation is a second entry beside the marketing site, so
      // it ships as its own HTML file and three.js never enters the homepage
      // bundle.
      input: {
        main: resolve(import.meta.dirname, 'index.html'),
        showcase: resolve(import.meta.dirname, 'showcase.html'),
      },
    },
  },
});
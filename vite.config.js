import { defineConfig } from 'vite';
import { copyFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

// Public input files remain in their existing, reviewed location. Copy only
// those two files; private project folders can never enter the site artifact.
export default defineConfig({
  root: 'student',
  base: './',
  publicDir: false,
  build: { outDir: '_site', emptyOutDir: true, sourcemap: false },
  plugins: [{
    name: 'copy-protected-aggregates',
    closeBundle() {
      const destination = resolve('student/_site/data');
      mkdirSync(destination, { recursive: true });
      for (const file of ['public_results.json', 'public_manifest.json']) {
        copyFileSync(resolve('student/data', file), resolve(destination, file));
      }
    }
  }]
});

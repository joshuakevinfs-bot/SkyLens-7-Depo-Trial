import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  root: "site",
  base: "/SkyLens-7-Depo-Trial/",
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        landing: resolve(import.meta.dirname, "site/index.html"),
        dashboard: resolve(import.meta.dirname, "site/dashboard/index.html"),
        sales: resolve(import.meta.dirname, "site/sales/index.html"),
      },
    },
  },
});

import path from "path";
import { fileURLToPath } from "url";

/** @type {import('next').NextConfig} */
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const isDev = process.env.NODE_ENV === "development";
const BACKEND_URL = process.env.LITELLM_BACKEND_URL ?? "http://localhost:4000";

const nextConfig = {
  // In dev: no static export so rewrites + HMR work.
  // In production: static export bundled into the Python package.
  ...(isDev ? {} : { output: "export" }),
  basePath: "",
  // Asset prefix only needed for production (Python serves at /litellm-asset-prefix).
  assetPrefix: isDev ? "" : "/litellm-asset-prefix",
  turbopack: {
    // Must be absolute; "." is no longer allowed
    root: __dirname,
  },
  // Dev only: proxy all non-UI/non-Next.js requests to the Python backend.
  // Enables NEXT_PUBLIC_USE_REWRITES=true mode in networking.tsx so the frontend
  // uses relative URLs and rewrites forward them to the backend.
  ...(isDev && {
    async redirects() {
      return [
        {
          // /ui/login → /login, /ui/foo → /foo, etc.
          // The /ui/ prefix only exists in the production static build served by the
          // Python backend. In dev the Next.js router serves pages without it.
          source: "/ui/:path*",
          destination: "/:path*",
          permanent: false,
        },
      ];
    },
    async rewrites() {
      return [
        {
          // Forward everything except Next.js internals and /ui/* (served by next dev)
          source: "/:path((?!ui|_next|litellm-asset-prefix).*)",
          destination: `${BACKEND_URL}/:path*`,
        },
      ];
    },
  }),
};

export default nextConfig;

This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Auth gate

The admin app sits behind HTTP Basic Auth via `src/middleware.ts`. Behaviour:

- If the env var `MEDRASH_ADMIN_PORTAL_KEY` is **unset**, the gate is a no-op (intended for local dev).
- If it is **set**, every request (except `_next/static`, `_next/image`, and `favicon.ico`) must present `Authorization: Basic base64("admin:<MEDRASH_ADMIN_PORTAL_KEY>")`. Otherwise the response is `401` with `WWW-Authenticate: Basic realm="MedRash Admin"`, so the browser shows the standard login prompt.

Set the secret in Netlify (Site → Build & deploy → Environment) as `MEDRASH_ADMIN_PORTAL_KEY`. Use username `admin` and the secret value as the password when the browser prompts.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.

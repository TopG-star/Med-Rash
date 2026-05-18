import type { Metadata } from "next";
import { Anybody, Hanken_Grotesk } from "next/font/google";
import "./globals.css";

const anybody = Anybody({
  variable: "--font-anybody",
  subsets: ["latin"],
});

const hankenGrotesk = Hanken_Grotesk({
  variable: "--font-hanken-grotesk",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "MedRash Admin",
  description: "MedRash admin console for sessions, quizzes, and analytics.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${anybody.variable} ${hankenGrotesk.variable} h-full antialiased`}
    >
      <body className="min-h-full bg-[var(--arena-background)] text-[var(--arena-ink)] font-[family-name:var(--font-hanken-grotesk)]">
        {children}
      </body>
    </html>
  );
}


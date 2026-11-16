import type { ReactNode } from "react";
import Analytics from "./analytics";
import "./globals.css";

export const metadata = {
  title: "TinyTimer",
  description: "A tiny menu bar timer for macOS. Vibe-code it in 30 minutes, or just download it.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  );
}

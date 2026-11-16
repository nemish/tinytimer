import type { ReactNode } from "react";
import Analytics from "./analytics";
import "./globals.css";

const title = "TinyTimer";
const description = "A tiny menu bar timer for macOS. Vibe-code it in 30 minutes, or just download it.";

export const metadata = {
  metadataBase: new URL("https://tinytimer.yaraoncode.me"), // makes the preview image URL absolute
  title,
  description,
  // The image itself is app/opengraph-image.png (drawn from ../og.html), picked up by file convention.
  openGraph: { title, description, url: "/", siteName: title, type: "website" },
  twitter: { card: "summary_large_image" },
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

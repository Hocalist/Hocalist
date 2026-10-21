import type { Metadata } from "next";
import "./globals.css";
import "./workspace.css";

export const metadata: Metadata = { title: "Hocalist Admin", description: "Hocalist Phase 1 administration preview", icons: { icon: "/brand/hocalist-icon.png", apple: "/brand/hocalist-icon.png" } };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}

import { getSiteSettings } from "@/lib/site-settings";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const settings = await getSiteSettings();
  return (
    <html lang={settings.locale}>
      <body>{children}</body>
    </html>
  );
}

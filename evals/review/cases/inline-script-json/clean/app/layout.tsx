import { toInlineScriptString } from "@/lib/inline-script";
import { getSiteSettings } from "@/lib/site-settings";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const settings = await getSiteSettings();
  return (
    <html lang={settings.locale}>
      <head>
        {settings.analyticsTagId && (
          <script
            dangerouslySetInnerHTML={{
              __html: `window.dataLayer = window.dataLayer || []; window.dataLayer.push({ tagId: ${toInlineScriptString(settings.analyticsTagId)} });`,
            }}
          />
        )}
      </head>
      <body>{children}</body>
    </html>
  );
}

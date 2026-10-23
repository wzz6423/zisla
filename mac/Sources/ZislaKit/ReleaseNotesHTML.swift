import Foundation
import ZislaCore

// Typography adapted from pluk-inc/markdown-preview at c94262cc19c90893cab55b8e545d269e6b651bb3.
// Copyright (c) 2026 Pluk. MIT license: Resources/ThirdPartyLicenses/MarkdownPreview-LICENSE.txt.
public enum ReleaseNotesHTML {
    public static func document(markdown: String, language: AppLanguage) -> String {
        let body = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        return """
        <!doctype html>
        <html lang="\(language.rawValue)" dir="\(language.isRightToLeft ? "rtl" : "ltr")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; base-uri 'none'; form-action 'none'">
          <style>
            :root {
              color-scheme: light dark;
              --text: -apple-system-label;
              --secondary: -apple-system-secondary-label;
              --grid: -apple-system-separator;
              --link: rgb(0, 104, 218);
              --code-bg: #f9f9f9;
              --code-border: #f0f0f0;
            }
            @media (prefers-color-scheme: dark) {
              :root { --link: rgb(65, 156, 255); --code-bg: #262626; --code-border: #323232; }
            }
            * { box-sizing: border-box; }
            body {
              margin: 0; padding: 28px 32px 40px; background: transparent; color: var(--text);
              font: 14px -apple-system, BlinkMacSystemFont, system-ui, sans-serif; line-height: 1.65;
              overflow-wrap: anywhere; text-align: start;
            }
            article { max-width: 720px; margin-inline: auto; }
            article > :first-child { margin-top: 0; }
            h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 1.4em 0 0.6em; }
            h1 { font-size: 2em; }
            h2 { font-size: 1.692em; }
            h3 { font-size: 1.308em; }
            h4 { font-size: 1.154em; }
            h5 { font-size: 1em; }
            h6 { font-size: 0.846em; }
            p, ul, ol { margin: 0.75em 0; }
            ul, ol { padding-inline-start: 2.1em; }
            li + li { margin-top: 0.4em; }
            a { color: var(--link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code { font: 0.9em ui-monospace, "SF Mono", Menlo, monospace; background: var(--code-bg); padding: 2px 5px; border-radius: 5px; }
            pre { background: var(--code-bg); border: 1px solid var(--code-border); border-radius: 8px; padding: 16px; overflow: auto; direction: ltr; }
            pre code { background: none; padding: 0; }
            blockquote { margin-inline: 0; padding-inline-start: 16px; border-inline-start: 3px solid var(--grid); color: var(--secondary); }
            table { display: block; border-collapse: collapse; max-width: 100%; overflow-x: auto; }
            th, td { border: 1px solid var(--grid); padding: 8px 12px; text-align: start; }
            th { background: var(--code-bg); font-weight: 600; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            figure { margin-inline: 0; }
            hr { border: 0; border-top: 1px solid var(--grid); margin: 1.5em 0; }
          </style>
        </head>
        <body><article>\(body)</article></body>
        </html>
        """
    }
}

// Nuvo palette — mirrors lib/core/theme tokens so the email reads as the
// same product: ink navy, Nuvo blue, off-white page.
const INK = '#07152B';
const BLUE = '#1D63FF';
const MUTED = '#66728A';
const FAINT = '#8B96A8';
const PAGE = '#F6F8FF';
const CARD = '#FFFFFF';
const CARD_EDGE = '#DCE5F2';
const CODE_BG = '#EEF5FF';
const FONT = "-apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const MONO = "ui-monospace, 'SF Mono', Menlo, Consolas, 'Courier New', monospace";

const SUBJECT = 'Your Nuvo verification code';

const PRIVACY_URL = 'https://getnuvo.net/privacy';
const TERMS_URL = 'https://getnuvo.net/terms';
const SITE_URL = 'https://getnuvo.net';

// Vertical rhythm is set with explicit-height spacer rows, not <br> or
// margins on text — Outlook ignores margin on many elements, and spacer
// cells render identically in Apple Mail, Gmail and Outlook.
const spacer = (h: number) =>
  `<tr><td style="height:${h}px;line-height:${h}px;font-size:0;">&nbsp;</td></tr>`;

function renderHtml(code: string): string {
  return `<!DOCTYPE html>
<html lang="en" dir="ltr" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${SUBJECT}</title>
</head>
<body style="margin:0;padding:0;background:${PAGE};font-family:${FONT};-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;">
Use this code to finish signing in to Nuvo.
</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${PAGE};">
  <tr>
    <td align="center" style="padding:40px 16px;">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" border="0"
        style="width:480px;max-width:100%;background:${CARD};border:1px solid ${CARD_EDGE};border-radius:16px;">
        <tr>
          <td style="padding:40px 36px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <!-- Wordmark: text, not an image, so the email reads correctly
                   with images blocked. -->
              <tr>
                <td style="font-size:13px;font-weight:800;letter-spacing:3px;color:${INK};">
                  NUVO
                </td>
              </tr>
              ${spacer(28)}
              <tr>
                <td style="font-size:24px;font-weight:800;line-height:1.3;color:${INK};">
                  Verify your email
                </td>
              </tr>
              ${spacer(14)}
              <tr>
                <td style="font-size:15px;line-height:1.6;color:${MUTED};">
                  Use this code to finish signing in to Nuvo.
                </td>
              </tr>
              ${spacer(28)}
              <!-- OTP: the code itself is plain contiguous text — letter-spacing
                   is a style, not a character, so copying yields a clean value. -->
              <tr>
                <td align="center" style="background:${CODE_BG};border-radius:12px;padding:26px 16px;">
                  <span style="font-family:${MONO};font-size:32px;font-weight:700;letter-spacing:8px;color:${INK};white-space:nowrap;">${code}</span>
                </td>
              </tr>
              ${spacer(20)}
              <tr>
                <td align="center" style="font-size:13px;line-height:1.5;color:${MUTED};">
                  This code expires soon.
                </td>
              </tr>
              ${spacer(28)}
              <tr>
                <td style="font-size:13px;line-height:1.6;color:${FAINT};">
                  If you didn&rsquo;t request this code, you can ignore this email.
                  Don&rsquo;t share this code with anyone.
                </td>
              </tr>
              ${spacer(32)}
              <tr>
                <td style="border-top:1px solid ${CARD_EDGE};font-size:0;line-height:0;">&nbsp;</td>
              </tr>
              ${spacer(24)}
              <tr>
                <td style="font-size:12px;line-height:1.6;color:${FAINT};">
                  Nuvo &middot;
                  <a href="${SITE_URL}" style="color:${BLUE};text-decoration:none;">getnuvo.net</a>
                  &nbsp;&middot;&nbsp;
                  <a href="${PRIVACY_URL}" style="color:${BLUE};text-decoration:none;">Privacy Policy</a>
                  &nbsp;&middot;&nbsp;
                  <a href="${TERMS_URL}" style="color:${BLUE};text-decoration:none;">Terms</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
`;
}

function renderText(code: string): string {
  return `Nuvo

Verify your email

Use this code to finish signing in to Nuvo:

${code}

This code expires soon.

If you didn't request this code, you can ignore this email. Don't share it with anyone.

— Nuvo
${SITE_URL}
Privacy Policy: ${PRIVACY_URL}
Terms: ${TERMS_URL}
`;
}

export async function sendVerificationCode(
  to: string,
  code: string,
  apiKey: string,
  fromEmail: string,
): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: `Nuvo <${fromEmail}>`,
      to: [to],
      subject: SUBJECT,
      html: renderHtml(code),
      text: renderText(code),
    }),
  });

  if (!res.ok) {
    // Surface status only — never log the code or key
    throw new Error(`Resend API returned ${res.status}`);
  }
}

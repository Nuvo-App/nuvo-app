import { EMAIL_LOGO_HEIGHT, EMAIL_LOGO_PNG_BASE64, EMAIL_LOGO_WIDTH } from './emailLogo';

// Nuvo palette: two base colors (navy ink + white/off-white) with Nuvo blue
// as the single accent. The thick navy outline + hard offset shadow is the
// brand signature, so the card keeps it (Outlook falls back to a flat border).
const INK = '#07152B';
const BLUE = '#1264FF';
const MUTED = '#5B6780';
const FAINT = '#7A869B';
const PAGE = '#F2F5FB';
const CARD = '#FFFFFF';
const HERO_DIVIDER = '#07152B';
const RULE = '#E3E9F3';
const CODE_BG = '#EAF1FF';
const FONT = "-apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const MONO = "ui-monospace, 'SF Mono', Menlo, Consolas, 'Courier New', monospace";

const SUBJECT = 'Your Nuvo verification code';

const PRIVACY_URL = 'https://getnuvo.net/privacy';
const TERMS_URL = 'https://getnuvo.net/terms';
const SITE_URL = 'https://getnuvo.net';

// The logo ships INSIDE the message as a CID inline attachment (content_id
// 'nuvo-logo'), so it renders in Gmail, Outlook (incl. desktop), Apple Mail and
// Yahoo with no external host to block, 404 or be filtered, and still shows
// when remote images are off. alt text + navy header keep it readable if not.
export const EMAIL_LOGO_CID = 'nuvo-logo';

// Vertical rhythm uses explicit-height spacer rows, not <br> or margins:
// Outlook ignores margin on many elements. Every cell carries an explicit
// bgcolor + color so Gmail/Outlook dark-mode inversion stays legible.
const spacer = (h: number, bg = CARD) =>
  `<tr><td bgcolor="${bg}" style="height:${h}px;line-height:${h}px;font-size:0;background:${bg};">&nbsp;</td></tr>`;

// Arena-card hero colors; one is picked per email. All are light enough for
// navy text and the white Nuvo mark (which carries its own navy edge).
export const HERO_COLORS = ['#FF8A65', '#FFC93C', '#B9A7FF', '#5EDC9B', '#6FB1FF', '#FF7A7A'];

export function renderHtml(code: string, hero?: string): string {
  const heroBg = hero ?? HERO_COLORS[Math.floor(Math.random() * HERO_COLORS.length)];
  const logoW = 92;
  const logoH = Math.round((logoW * EMAIL_LOGO_HEIGHT) / EMAIL_LOGO_WIDTH);
  // Arena card: colored hero + light body, thick navy outline, hard offset
  // shadow. Gmail drops CSS box-shadow, so the shadow is a navy wrapper cell;
  // the hero cell's top radii match the card's inner radius so nothing pokes
  // past the rounded corners.
  return `<!DOCTYPE html>
<html lang="en" dir="ltr" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<!--[if mso]><xml><o:OfficeDocumentSettings><o:AllowPNG/><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml><![endif]-->
<title>${SUBJECT}</title>
</head>
<body bgcolor="${PAGE}" style="margin:0;padding:0;width:100%;background:${PAGE};font-family:${FONT};-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:${PAGE};">
Your Nuvo code is ${code}. It expires in 10 minutes.&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;
</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" align="center" bgcolor="${PAGE}" style="width:100%;background:${PAGE};">
  <tr>
    <td align="center" bgcolor="${PAGE}" style="padding:36px 16px 44px 16px;background:${PAGE};">
      <!--[if mso]><table role="presentation" align="center" width="520" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
      <table role="presentation" align="center" width="520" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:520px;">
        <tr>
          <td bgcolor="${INK}" style="background:${INK};border-radius:24px;padding:0 7px 7px 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border:3px solid ${INK};border-radius:24px;">
              <tr>
                <td align="center" bgcolor="${heroBg}" style="background:${heroBg};border-radius:21px 21px 0 0;padding:34px 24px 30px 24px;">
                  <img src="cid:${EMAIL_LOGO_CID}" width="${logoW}" height="${logoH}" alt="Nuvo" border="0"
                    style="display:block;margin:0 auto;border:0;outline:none;text-decoration:none;width:${logoW}px;height:${logoH}px;font-family:${FONT};font-size:24px;font-weight:800;letter-spacing:4px;color:${INK};">
                  <div style="height:18px;line-height:18px;font-size:0;">&nbsp;</div>
                  <div style="font-family:${FONT};font-size:28px;font-weight:800;line-height:1.2;color:${INK};">Verify your email</div>
                  <div style="height:8px;line-height:8px;font-size:0;">&nbsp;</div>
                  <div style="font-family:${FONT};font-size:16px;line-height:1.5;color:${INK};">Enter this code in the Nuvo app to finish signing in.</div>
                </td>
              </tr>
              <tr>
                <td bgcolor="${HERO_DIVIDER}" height="3" style="background:${HERO_DIVIDER};height:3px;line-height:3px;font-size:0;">&nbsp;</td>
              </tr>
              <tr>
                <td align="center" bgcolor="${CARD}" style="background:${CARD};border-radius:0 0 21px 21px;padding:30px 32px 28px 32px;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                    <!-- OTP: plain contiguous text; letter-spacing is a style, so copying gives a clean value. -->
                    <tr>
                      <td align="center" bgcolor="${CODE_BG}" style="background:${CODE_BG};border:2px solid ${INK};border-radius:16px;padding:24px 12px;">
                        <span style="font-family:${MONO};font-size:40px;line-height:1;font-weight:700;letter-spacing:10px;color:${INK};white-space:nowrap;">${code}</span>
                      </td>
                    </tr>
                    ${spacer(16)}
                    <tr>
                      <td align="center" bgcolor="${CARD}" style="background:${CARD};font-family:${FONT};font-size:14px;line-height:1.5;color:${MUTED};">
                        This code expires in <strong style="color:${INK};">10 minutes</strong>.
                      </td>
                    </tr>
                    ${spacer(22)}
                    <tr>
                      <td align="center" bgcolor="${CARD}" style="background:${CARD};font-family:${FONT};font-size:13px;line-height:1.6;color:${FAINT};">
                        Didn&rsquo;t request this? You can safely ignore this email.<br>
                        Never share this code with anyone.
                      </td>
                    </tr>
                    ${spacer(24)}
                    <tr>
                      <td bgcolor="${RULE}" height="1" style="background:${RULE};height:1px;line-height:1px;font-size:0;">&nbsp;</td>
                    </tr>
                    ${spacer(18)}
                    <tr>
                      <td align="center" bgcolor="${CARD}" style="background:${CARD};font-family:${FONT};font-size:12px;line-height:1.6;color:${FAINT};">
                        <a href="${SITE_URL}" style="color:${BLUE};text-decoration:none;font-weight:600;">getnuvo.net</a>
                        &nbsp;&middot;&nbsp;
                        <a href="${PRIVACY_URL}" style="color:${BLUE};text-decoration:none;">Privacy</a>
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
      <!--[if mso]></td></tr></table><![endif]-->
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

This code expires in 10 minutes.

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
      attachments: [
        {
          filename: 'nuvo-logo.png',
          content: EMAIL_LOGO_PNG_BASE64,
          content_type: 'image/png',
          content_id: EMAIL_LOGO_CID,
        },
      ],
    }),
  });

  if (!res.ok) {
    // Surface status only — never log the code or key
    throw new Error(`Resend API returned ${res.status}`);
  }
}

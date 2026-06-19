const EMAIL_HTML = (code: string) => `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#F6F8FF;font-family:sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center" style="padding:40px 16px;">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;border:1px solid #DCE5F2;">
        <tr>
          <td style="padding:40px 36px;">
            <div style="font-size:13px;font-weight:800;letter-spacing:2px;color:#66728A;margin-bottom:24px;">NUVO</div>
            <h2 style="margin:0 0 12px;font-size:24px;font-weight:900;color:#07152B;">Your verification code</h2>
            <p style="margin:0 0 28px;font-size:15px;color:#66728A;line-height:1.5;">
              Use the code below to verify your Nuvo account. It expires in 10 minutes.
            </p>
            <div style="background:#EEF5FF;border-radius:12px;padding:28px;text-align:center;margin-bottom:28px;">
              <span style="font-size:44px;font-weight:900;letter-spacing:10px;color:#07152B;">${code}</span>
            </div>
            <p style="margin:0;font-size:12px;color:#8B96A8;line-height:1.5;">
              If you did not request this code, you can safely ignore this email. Do not share this code with anyone.
            </p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
`;

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
      from: fromEmail,
      to: [to],
      subject: 'Your Nuvo code',
      html: EMAIL_HTML(code),
    }),
  });

  if (!res.ok) {
    // Surface status only — never log the code or key
    throw new Error(`Resend API returned ${res.status}`);
  }
}

// Escape all visitor content before placing it in HTML, including attributes.
const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

export function supportEmail({name, email, topic, message}) {
  const sender = name.trim() || 'Wand user';
  const content = message.trim();
  const replyURL = `mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent(`Re: Wand support: ${topic}`)}`;
  return {
    text: `Wand · Support\n\nNew support message\nFrom: ${sender}\nReply to: ${email}\nTopic: ${topic}\n\n${content}\n\nReply to this email to respond directly to ${sender}.\nhttps://getwand.app/support/`,
    html: `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wand support</title></head>
<body style="margin:0;padding:0;background-color:#f5f5ed;color:#263226;font-family:Arial,Helvetica,sans-serif;">
<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">New ${escapeHTML(topic.toLowerCase())} message from ${escapeHTML(sender)}.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5ed;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;">
<tr><td style="padding:8px 8px 24px;"><a href="https://getwand.app/" style="font-size:32px;font-weight:400;letter-spacing:-1px;color:#263226;text-decoration:none;">wand<span style="color:#6b784d;">.</span></a><span style="font-size:13px;color:#68705f;padding-left:14px;">Support</span></td></tr>
<tr><td style="background-color:#ffffff;border:1px solid #dfe3d7;border-radius:20px;padding:32px 24px;">
<p style="margin:0 0 12px;font-size:12px;font-weight:600;letter-spacing:1px;color:#65744b;">${escapeHTML(topic.toUpperCase())}</p>
<h1 style="margin:0 0 24px;font-size:26px;line-height:1.25;font-weight:400;color:#263226;">New support message</h1>
<p style="margin:0 0 4px;font-size:16px;line-height:1.5;color:#263226;">${escapeHTML(sender)}</p>
<p style="margin:0 0 24px;font-size:14px;line-height:1.5;overflow-wrap:anywhere;word-break:break-word;"><a href="${escapeHTML(replyURL)}" style="color:#566944;text-decoration:underline;">${escapeHTML(email)}</a></p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="border-top:1px solid #e6e9e0;padding:24px 0;font-size:16px;line-height:1.7;color:#30382d;overflow-wrap:anywhere;word-break:break-word;">${escapeHTML(content).replace(/\r\n|\r|\n/g,'<br>')}</td></tr></table>
<table role="presentation" cellpadding="0" cellspacing="0"><tr><td bgcolor="#2d402b" style="border-radius:24px;text-align:center;"><a href="${escapeHTML(replyURL)}" style="display:inline-block;padding:14px 24px;border:1px solid #2d402b;border-radius:24px;color:#ffffff;font-size:14px;text-decoration:none;font-weight:600;">Reply to ${escapeHTML(sender)}</a></td></tr></table>
<p style="margin:18px 0 0;font-size:13px;line-height:1.6;color:#68705f;">You can also reply directly to this email.</p>
</td></tr>
<tr><td style="padding:24px 8px;font-size:12px;line-height:1.6;color:#68705f;">Sent through the <a href="https://getwand.app/support/" style="color:#566944;text-decoration:underline;">Wand support form</a>.</td></tr>
</table></td></tr></table></body></html>`
  };
}

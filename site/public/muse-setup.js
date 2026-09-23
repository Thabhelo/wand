window.wandMuseSetupPrompt = "I want to set up Wand (https://getwand.app) so I can control my Mac from my phone, and so you can operate it for me.\n\nWand is a menu-bar app for Mac with web controls at https://app.getwand.app. It lets you mute or lock my Mac, change volume, check battery, storage and memory, control playback, and open or close apps. These are examples, not the full list. Explore the web app to see what is available.\n\nI have already downloaded and opened Wand on my Mac. Do everything you can yourself. Only ask me for steps that require me:\n\n1. Open https://app.getwand.app and use Google sign-in. If you have a supported secure sign-in or vault interface, let me enter credentials there. Otherwise, let me take over Google's sign-in screen. Never ask for a password in chat.\n2. Tell me to click Connect in the Wand Mac app and sign in with the same Google account. If my Mac is already connected, skip this step.\n3. Complete the web setup as far as your tools allow. Keep checking the device list for up to two minutes until my Mac is Online; don't ask me to announce when it connects. If it stays offline, inspect the connection status and explain the next step. Ask for a pairing code only if automatic linking fails.\n4. Check my Mac's battery and report the actual result. Don't claim it works until you have a successful response.\n5. When I ask you to do something on my Mac, use Wand's web controls and report what happened. Follow any confirmations and permissions required for the action.\n\nIf Google requires two-factor approval or another security challenge, ask me to complete it in Google's sign-in flow. Don't read my emails to get around it. Troubleshoot other issues yourself where possible.\n\nThis setup uses Wand's website. It does not add Wand as a native Muse connection.";
// Loaded by muse-setup.js with the shared prompt text.
for (const button of document.querySelectorAll('[data-copy-muse]')) {
 button.addEventListener('click', async () => {
  const container=button.closest('[data-muse-setup]');
  const status=container.querySelector('[role="status"]');
  try {
   await navigator.clipboard.writeText(window.wandMuseSetupPrompt);
   status.textContent='Copied. Paste it into Muse.';
  } catch {
   let field=container.querySelector('textarea');
   if(!field){field=document.createElement('textarea');field.readOnly=true;field.rows=10;field.setAttribute('aria-label','Muse setup prompt');field.style.cssText='width:100%;box-sizing:border-box;font:inherit;margin-top:12px';container.append(field);}
   const disclosure=field.closest('details');if(disclosure)disclosure.open=true;
   field.value=window.wandMuseSetupPrompt;field.hidden=false;field.focus();field.select();field.setSelectionRange(0,field.value.length);
   status.textContent='Copy the prompt below, then paste it into Muse.';
  }
 });
}

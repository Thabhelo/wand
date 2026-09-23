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

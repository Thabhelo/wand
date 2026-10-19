'use strict';
const form=document.getElementById('support-form');
const status=document.getElementById('send-status');
window.supportCheckFailed=()=>{status.textContent='The security check could not load. Please retry or email support@getwand.app.';};
window.supportCheckExpired=()=>{status.textContent='The security check expired. Please complete it again.';};
form.addEventListener('submit',async event=>{
 event.preventDefault();
 const button=form.querySelector('button[type="submit"]');
 if(button.disabled||!form.reportValidity())return;
 const fields=new FormData(form);
 if(!fields.get('cf-turnstile-response')){status.textContent='Please complete the security check before sending.';return;}
 button.disabled=true;button.textContent='Sending…';status.textContent='';status.removeAttribute('data-error');
 try{
  const response=await fetch('/api/support',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.fromEntries(fields)),signal:AbortSignal.timeout(25000)});
  const result=await response.json();
  if(!response.ok)throw new Error(result.message||'We couldn’t send your message. Please try again.');
  status.textContent=result.message;form.reset();
 }catch(error){status.dataset.error='true';status.textContent=error.name==='TimeoutError'?'Sending took too long to confirm. Please wait a minute before trying again.':error instanceof TypeError?'Check your connection and try again.':error.message;}
 finally{window.turnstile?.reset();button.disabled=false;button.textContent='Send message';}
});

'use strict';
const form=document.getElementById('support-form');
const status=document.getElementById('send-status');
form.addEventListener('submit',async event=>{
 event.preventDefault();
 const button=form.querySelector('button[type="submit"]');
 if(button.disabled||!form.reportValidity())return;
 button.disabled=true;button.textContent='Sending…';status.textContent='';status.removeAttribute('data-error');
 try{
  const response=await fetch('/api/support',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.fromEntries(new FormData(form))),signal:AbortSignal.timeout(25000)});
  const result=await response.json();
  if(!response.ok)throw new Error(result.message||'We couldn’t send your message. Please try again.');
  status.textContent=result.message;form.reset();
 }catch(error){status.dataset.error='true';status.textContent=error.name==='TimeoutError'?'Sending took too long to confirm. Please wait a minute before trying again.':error instanceof TypeError?'Check your connection and try again.':error.message;}
 finally{button.disabled=false;button.textContent='Send message';}
});

'use strict';
document.getElementById('copy-address').addEventListener('click',async()=>{
 const address=document.getElementById('support-address').textContent;
 const status=document.getElementById('copy-status');
 try{await navigator.clipboard.writeText(address);status.textContent='Email copied. Paste it into your email app.'}
 catch{status.textContent='Copy the email address above and paste it into your email app.'}
});

/* Device-scoped, in-memory app discovery. No inventory is saved in browser storage. */
class WandAppPicker {
 constructor(root,{load,current=false,onchange=()=>{}}){
  this.load=load;this.current=current;this.onchange=onchange;this.generation=0;this.apps=[];this.device=null;
  const label=document.createElement('label');label.textContent='App';
  this.search=document.createElement('input');this.search.type='search';this.search.placeholder='Find an app';this.search.setAttribute('aria-label','Find an installed app');
  this.select=document.createElement('select');this.select.setAttribute('aria-label','App, most recently opened first');
  this.manual=document.createElement('input');this.manual.placeholder='App name or bundle ID';this.manual.maxLength=200;this.manual.hidden=true;this.manual.setAttribute('aria-label','Other app name or bundle ID');
  this.note=document.createElement('small');this.note.setAttribute('role','status');
  this.retry=document.createElement('button');this.retry.type='button';this.retry.textContent='Refresh apps';this.retry.onclick=()=>this.setDevice(this.device,true,this.online);
  label.append(this.select);root.append(this.search,label,this.manual,this.note,this.retry);
  this.search.oninput=()=>{this.render();this.onchange()};this.select.onchange=()=>{this.manual.hidden=this.select.value!=='__manual';if(!this.manual.hidden)this.manual.focus();this.onchange()};this.manual.oninput=onchange;
  this.render();
 }
 render(){const old=this.select.value;this.select.replaceChildren(new Option(this.current?'Current app':'Choose an app',''));const term=this.search.value.trim().toLocaleLowerCase();for(const app of this.apps.filter(a=>a.name.toLocaleLowerCase().includes(term)||a.bundle_id.toLowerCase().includes(term))){const duplicates=this.apps.some(b=>b!==app&&b.name===app.name);this.select.add(new Option(app.name+(duplicates?' · '+app.bundle_id:'')+(app.running?' · open':''),app.bundle_id))}this.select.add(new Option('Other…','__manual'));if(Array.from(this.select.options).some(o=>o.value===old))this.select.value=old;this.manual.hidden=this.select.value!=='__manual'}
 async setDevice(id,force=false,online=true){if(!force&&id===this.device&&online===this.online)return;this.device=id;this.online=online;const generation=++this.generation;this.apps=[];this.search.value='';this.manual.value='';this.select.value='';this.render();this.onchange();this.note.textContent=!id?'Choose a Mac.':!online?'Your Mac is offline.':'Loading apps…';this.retry.disabled=!id||!online;if(!id||!online)return;this.retry.disabled=true;
  try{let offset=0;const found=new Map();for(let page=0;page<200;page++){if(generation!==this.generation)return;const result=await this.load(id,offset);if(generation!==this.generation)return;for(const app of result.apps)if(!window.WandFeedback||WandFeedback.safeApp(app))found.set(app.bundle_id,app);this.apps=Array.from(found.values());this.render();if(result.next_offset===null){this.note.textContent=this.apps.length?'Recent apps first. Others A–Z.':'No apps found. Choose Other to enter a name.';return}if(result.next_offset<=offset)throw Error('The app list could not be completed. Try Refresh apps.');offset=result.next_offset;this.note.textContent='Loading more apps…'}}catch(error){if(generation===this.generation)this.note.textContent=error.message||'Could not load apps. Choose Other or try again.'}finally{if(generation===this.generation)this.retry.disabled=false}
 }
 value(){if(this.select.value==='__manual'){const text=this.manual.value.trim();if(!text)throw Error('Enter an app name or bundle ID.');return {params:/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(text)?{bundle_id:text}:{app_name:text},label:text}}const app=this.apps.find(a=>a.bundle_id===this.select.value);if(app)return {params:{bundle_id:app.bundle_id},label:app.name};if(this.current)return {params:{},label:'Current app'};throw Error('Choose an app first.')}
}
window.WandAppPicker=WandAppPicker;

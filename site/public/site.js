const examples={music:['Put on some music.','Play or pause your music.','Wand can play or pause music in Music or Spotify when either app is open.'],app:['Open Calculator on my Mac.','Open an app on your Mac.','Wand opens the app you choose on your Mac.'],shortcut:['Run my focus routine.','Run a Shortcut you approved.','Wand runs only the Shortcuts you add in its settings. Only add Shortcuts you trust.']};
for(const button of document.querySelectorAll('[data-demo]'))button.addEventListener('click',()=>{const value=examples[button.dataset.demo];document.querySelector('#demo-request').textContent=value[0];document.querySelector('#demo-title').textContent=value[1];document.querySelector('#demo-detail').textContent=value[2];for(const other of document.querySelectorAll('[data-demo]'))other.setAttribute('aria-pressed',String(other===button))});

const film=document.querySelector('#muse-film');
if(film){
  const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
  film.muted=true;
  film.addEventListener('contextmenu',event=>event.preventDefault());
  if(!reducedMotion.matches&&!navigator.connection?.saveData)film.play().catch(()=>{});
  reducedMotion.addEventListener('change',event=>{if(event.matches)film.pause()});
  let resumeWhenVisible=false;
  new IntersectionObserver(entries=>{for(const entry of entries){if(!entry.isIntersecting){resumeWhenVisible=!film.paused;film.pause()}else if(resumeWhenVisible&&!reducedMotion.matches){resumeWhenVisible=false;film.play().catch(()=>{})}}},{threshold:0.1}).observe(film);
}

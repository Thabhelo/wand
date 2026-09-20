const examples={mute:['My Mac is making noise at home. Mute it.','Quiet the whole Mac.','Mute your Mac’s sound output, including a video left playing in a browser.'],quit:['Quit Zoom on my Mac.','Close the app you left open.','Muse asks you to confirm before Wand requests a normal quit. If the app needs your attention, Wand tells you.'],battery:['Is my Mac charging?','Check the laptop back at home.','See your Mac’s battery level and whether it’s charging, without going back to check.']};
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

// Small, spring-like pointer response; no movement on touch or reduced motion.
const scene=document.querySelector('.magic-scene');
const motionOK=matchMedia('(hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference)');
if(scene){
  let frame=0;
  const reset=()=>{cancelAnimationFrame(frame);scene.style.setProperty('--mx','0');scene.style.setProperty('--my','0');scene.classList.remove('is-hovered')};
  scene.addEventListener('pointermove',event=>{
    if(!motionOK.matches)return;
    const box=scene.getBoundingClientRect();
    const x=(event.clientX-box.left)/box.width*2-1,y=(event.clientY-box.top)/box.height*2-1;
    cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{scene.style.setProperty('--mx',String(x));scene.style.setProperty('--my',String(y));scene.classList.add('is-hovered')});
  });
  scene.addEventListener('pointerleave',reset);motionOK.addEventListener('change',reset);
}
const motionSections=document.querySelectorAll('.demo-card,.site-footer');
const motionObserver=new IntersectionObserver(entries=>{for(const entry of entries)entry.target.classList.toggle('motion-visible',entry.isIntersecting)},{threshold:0.15});
motionSections.forEach(section=>motionObserver.observe(section));

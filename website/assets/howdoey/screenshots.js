(() => {
  const slides = [
    {src:'assets/howdoey/guide-attach.png', caption:'Find the attachment button', alt:'Howdoey highlights Gmail’s Attach files paperclip and gives the next instruction.'},
    {src:'assets/howdoey/guide-file.png', caption:'Choose the right file', alt:'The macOS file picker has recipebook.jpg selected; Howdoey explains the Open button.'},
    {src:'assets/howdoey/guide-done.png', caption:'Finish with confidence', alt:'The recipe book image is attached to the Gmail draft, and Howdoey confirms completion.'}
  ];
  const carousel = document.getElementById('guide-carousel');
  const image = document.getElementById('guide-image');
  const enlarge = document.getElementById('guide-enlarge');
  const caption = document.getElementById('guide-caption');
  const position = document.getElementById('guide-position');
  const pause = document.getElementById('guide-pause');
  const dialog = document.getElementById('screenshot-dialog');
  const full = document.getElementById('screenshot-full');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let index = 0, paused = motion.matches, hovered = false, focused = false, visible = true, timer;
  function show(next) {
    index = (next + slides.length) % slides.length;
    const slide = slides[index];
    image.src = slide.src; image.alt = slide.alt;
    enlarge.dataset.screenshot = slide.src; enlarge.dataset.caption = slide.caption;
    caption.textContent = slide.caption; position.textContent = `${index+1} / ${slides.length}`;
  }
  function schedule() {
    clearInterval(timer);
    pause.textContent = paused ? 'Play' : 'Pause';
    pause.setAttribute('aria-label', paused ? 'Play screenshot rotation' : 'Pause screenshot rotation');
    if (!paused && !hovered && !focused && visible && !document.hidden && !dialog.open) timer = setInterval(() => show(index+1), 6000);
  }
  document.getElementById('guide-previous').addEventListener('click',()=>{show(index-1);schedule();});
  document.getElementById('guide-next').addEventListener('click',()=>{show(index+1);schedule();});
  pause.addEventListener('click',()=>{paused=!paused;schedule();});
  carousel.addEventListener('pointerenter',()=>{hovered=true;schedule();});
  carousel.addEventListener('pointerleave',()=>{hovered=false;schedule();});
  carousel.addEventListener('focusin',()=>{focused=true;schedule();});
  carousel.addEventListener('focusout',event=>{if(!carousel.contains(event.relatedTarget)){focused=false;schedule();}});
  carousel.addEventListener('keydown',event=>{
    if(event.key==='ArrowLeft'||event.key==='ArrowRight'){event.preventDefault();show(index+(event.key==='ArrowLeft'?-1:1));schedule();}
  });
  document.addEventListener('visibilitychange',schedule);
  motion.addEventListener('change',()=>{paused=motion.matches;schedule();});
  if ('IntersectionObserver' in window) new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;schedule();}).observe(carousel);
  document.querySelectorAll('[data-screenshot]').forEach(button=>button.addEventListener('click',()=>{
    full.src=button.dataset.screenshot; full.alt=button.querySelector('img').alt;
    document.getElementById('screenshot-title').textContent=button.dataset.caption;
    dialog.showModal();schedule();
  }));
  document.getElementById('screenshot-close').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('close',schedule);
  dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
  slides.slice(1).forEach(slide=>{const preload=new Image();preload.src=slide.src;});
  schedule();
})();

for (const button of document.querySelectorAll('[data-copy-link]')) {
  button.addEventListener('click', async () => {
    const status = button.parentElement.querySelector('.copy-status');
    try {
      await navigator.clipboard.writeText(button.dataset.copyLink);
      status.textContent = 'Link copied';
    } catch {
      status.textContent = 'Copy the page address from your browser.';
    }
  });
}

for (const figure of document.querySelectorAll('.architecture')) {
  const buttons = [...figure.querySelectorAll('[data-flow]')];
  const detail = figure.querySelector('.flow-detail');
  const select = button => {
    for (const item of buttons) item.setAttribute('aria-pressed', String(item === button));
    figure.dataset.step = button.dataset.flow;
    detail.textContent = button.parentElement.querySelector('p').textContent;
  };
  figure.classList.add('enhanced');
  detail.hidden = false;
  for (const button of buttons) button.addEventListener('click', () => select(button));
  select(buttons[0]);
}

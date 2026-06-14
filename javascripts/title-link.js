document$.subscribe(() => {
  const logo = document.querySelector('.md-header__button.md-logo');
  if (!logo) return;
  const home = logo.getAttribute('href');
  const span = document.querySelector(
    '.md-header__title .md-header__topic:not([data-md-component]) .md-ellipsis'
  );
  if (!span || span.querySelector('a.md-header__title-link')) return;
  const a = document.createElement('a');
  a.className = 'md-header__title-link';
  a.href = home;
  while (span.firstChild) a.appendChild(span.firstChild);
  span.appendChild(a);
});

document$.subscribe(() => {
  const here = location.hostname;
  document.querySelectorAll('.md-content a[href]').forEach((a) => {
    const href = a.getAttribute('href');
    if (!/^https?:\/\//i.test(href)) return;
    if (a.hostname === here) return;
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
  });
});

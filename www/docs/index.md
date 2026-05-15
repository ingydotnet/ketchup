---
title: Ketchup
hide:
- navigation
- toc
---

<style>
  .md-header, .md-tabs, .md-footer { display: none; }
</style>

Loading today's report...

<noscript>
<a href="reports/">Browse all reports</a>
</noscript>

<script>
(async function () {
  const status = document.querySelector('.md-content p');
  try {
    const fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Toronto',
      year: 'numeric', month: '2-digit', day: '2-digit',
    });
    const today = fmt.format(new Date()).replace(/-/g, '');
    const r = await fetch('dates.json', { cache: 'no-store' });
    const dates = await r.json();
    if (!dates.length) throw new Error('no dates');
    const target = dates.find(d => d <= today) || dates[0];
    window.location.replace('reports/' + target + '/');
  } catch (e) {
    if (status) {
      status.innerHTML =
        'Could not load today\'s report (' + e.message +
        '). <a href="reports/">Browse all reports</a>.';
    }
  }
})();
</script>

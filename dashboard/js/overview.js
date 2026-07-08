// js/overview.js — Overview page: stat cards + system info rows.
const Overview = (() => {
  async function load() {
    const [profs, info, cs] = await Promise.all([
      Api.call('/api/profiles'),
      Api.call('/api/info'),
      Api.call('/api/cache/stats'),
    ]);
    const profiles = Array.isArray(profs) ? profs : [];

    document.getElementById('sv-p').textContent = profiles.length;
    document.getElementById('sv-h').textContent = cs?.streams?.hits ?? '0';
    document.getElementById('sv-k').textContent = cs?.streams?.keys ?? '0';

    renderSys(info);
  }

  function renderSys(info) {
    const rows = [
      ['Public URL', info?.publicUrl || '(request host)'],
      ['Local address', info?.nasIp ? `${info.nasIp}:${info.port || 7000}` : '(not set)'],
      ['TorBox plan', info?.plan || 'Pro'],
      ['Redis', info?.redis || 'connected'],
      ['Uptime', info?.uptime || '—'],
    ];
    document.getElementById('sys-rows').innerHTML = rows
      .map(r => `<div class="srow"><span class="srow-l">${r[0]}</span><span class="srow-r">${r[1]}</span></div>`)
      .join('');
  }

  return { load };
})();

registerOnEnter('dash', () => Overview.load());

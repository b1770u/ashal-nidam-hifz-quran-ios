/*
 * iOS: loaded after the app's main script. WKWebView cannot intercept https requests like
 * Android does, so mushaf pages saved on the phone are served through Capacitor's local file
 * URL instead, and pages seen online are saved in the background for next time.
 */
(function () {
  const IOS = window.__IOS;
  if (!IOS || typeof window.getMushafPageSvgUrl !== 'function') return;
  const online = window.getMushafPageSvgUrl;
  window.getMushafPageSvgUrl = function (pageNum, riwayah) {
    const edition = riwayah === 'warsh' ? 'warsh-kfqc' : 'hafs-kfqc';
    const num = String(Math.max(1, Math.min(604, Number(pageNum) || 1))).padStart(3, '0');
    const saved = IOS.cachedPages[edition];
    if (saved && saved.has(num) && IOS.root) {
      return window.Capacitor.convertFileSrc('file://' + IOS.root + '/pages/' + edition + '/' + num + '.svg');
    }
    try { IOS.QN.cachePage({ edition, num }); } catch (e) {}
    return online(pageNum, riwayah);
  };
})();

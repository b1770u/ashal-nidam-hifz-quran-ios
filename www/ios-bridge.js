/*
 * iOS adapter: exposes the same `window.AndroidBridge` API that the shared web app
 * (www/index.html, identical to the Android app) already uses, backed by the native
 * QuranNative Capacitor plugin. Loaded before the app's main script.
 */
(function () {
  const C = window.Capacitor;
  if (!C || !C.isNativePlatform || !C.isNativePlatform()) return;
  const QN = C.registerPlugin('QuranNative');

  const IOS_REPO = 'b1770u/ashal-nidam-hifz-quran-ios';
  const RELEASES_PAGE = `https://github.com/${IOS_REPO}/releases/latest`;
  const RECITERS = [
    { id: 'yassin', name: 'ياسين الجزائري', riwayah: 'warsh', mb: 640, folder: 'warsh/warsh_yassin_al_jazaery_64kbps' },
    { id: 'abdulbasit_warsh', name: 'عبد الباسط عبد الصمد', riwayah: 'warsh', mb: 1300, folder: 'warsh/warsh_Abdul_Basit_128kbps' },
    { id: 'dosary_warsh', name: 'إبراهيم الدوسري', riwayah: 'warsh', mb: 1200, folder: 'warsh/warsh_ibrahim_aldosary_128kbps' },
    { id: 'shuraym', name: 'سعود الشريم', riwayah: 'hafs', mb: 440, folder: 'Saood_ash-Shuraym_64kbps' },
    { id: 'husary', name: 'محمود خليل الحصري', riwayah: 'hafs', mb: 650, folder: 'Husary_64kbps' },
    { id: 'husary_muallim', name: 'الحصري (المعلّم)', riwayah: 'hafs', mb: 1500, folder: 'Husary_Muallim_128kbps' },
    { id: 'minshawy', name: 'محمد صديق المنشاوي', riwayah: 'hafs', mb: 1100, folder: 'Minshawy_Murattal_128kbps' },
    { id: 'alafasy', name: 'مشاري العفاسي', riwayah: 'hafs', mb: 520, folder: 'Alafasy_64kbps' },
    { id: 'abdulbasit', name: 'عبد الباسط عبد الصمد', riwayah: 'hafs', mb: 600, folder: 'Abdul_Basit_Murattal_64kbps' },
    { id: 'sudais', name: 'عبد الرحمن السديس', riwayah: 'hafs', mb: 420, folder: 'Abdurrahmaan_As-Sudais_64kbps' },
    { id: 'maher', name: 'ماهر المعيقلي', riwayah: 'hafs', mb: 450, folder: 'Maher_AlMuaiqly_64kbps' }
  ];
  const EMPTY_STATUS = { audio: {}, pagesWarsh: 0, pagesHafs: 0, tafsir: 0, totalAyahs: 6236, totalPages: 604, bytes: 0, running: false, progress: null };

  // WebKit's own speech API does not work inside apps; the native one is used instead.
  try { window.webkitSpeechRecognition = undefined; window.SpeechRecognition = undefined; } catch (e) {}

  const IOS = window.__IOS = {
    QN,
    root: '',
    version: window.__IOS_APP_VERSION__ || '',
    cachedPages: { 'warsh-kfqc': new Set(), 'hafs-kfqc': new Set() },
    offline: null,
    pendingDone: '',
    backupInfo: { location: '', time: 0 }
  };

  // ---- bundled data (read synchronously, like the Android bridge) ----
  const dataCache = {};
  function loadJSON(name) {
    if (dataCache[name]) return dataCache[name];
    const x = new XMLHttpRequest();
    x.open('GET', 'data/' + name, false);
    x.send(null);
    dataCache[name] = JSON.parse(x.responseText);
    return dataCache[name];
  }

  // ---- state kept fresh from native ----
  let lastOfflineJson = '';
  function refreshOffline() {
    return QN.offlineStatus().then((s) => {
      IOS.offline = s;
      const j = JSON.stringify(s);
      if (j !== lastOfflineJson) {
        lastOfflineJson = j;
        try { if (typeof window.refreshOfflineUI === 'function') window.refreshOfflineUI(); } catch (e) {}
      }
    }).catch(() => {});
  }
  let refreshTimer = null;
  function scheduleRefresh() {
    if (refreshTimer) return;
    refreshTimer = setTimeout(() => { refreshTimer = null; refreshOffline(); }, 300);
  }
  function refreshBackupInfo() {
    return QN.autoBackupInfo().then((i) => { IOS.backupInfo = i; }).catch(() => {});
  }

  QN.appInfo().then((i) => {
    IOS.root = i.offlineRoot || '';
    if (i.version) IOS.version = i.version;
  }).catch(() => {});
  Object.keys(IOS.cachedPages).forEach((ed) => {
    QN.cachedPages({ edition: ed }).then((r) => { (r.pages || []).forEach((n) => IOS.cachedPages[ed].add(n)); }).catch(() => {});
  });
  refreshOffline();
  refreshBackupInfo();

  QN.addListener('offline', (p) => {
    IOS.offline = Object.assign({}, IOS.offline || EMPTY_STATUS, { running: !p.finished, progress: p });
    if (typeof window.onOfflineProgress === 'function') window.onOfflineProgress(p);
    if (p.finished) {
      refreshOffline();
      ['warsh-kfqc', 'hafs-kfqc'].forEach((ed) => QN.cachedPages({ edition: ed }).then((r) => { (r.pages || []).forEach((n) => IOS.cachedPages[ed].add(n)); }));
    }
  });
  QN.addListener('audio', (s) => { if (typeof window.onNativeAudio === 'function') window.onNativeAudio(s); });
  QN.addListener('speech', (d) => {
    const ns = window.__nativeSpeech;
    if (!ns) return;
    if (d.type === 'result') ns.result(d.text || '', !!d.isFinal);
    else if (d.type === 'end') ns.end();
    else if (d.type === 'error') ns.error(d.code || 'aborted');
  });
  QN.addListener('pageCached', (d) => { (IOS.cachedPages[d.edition] = IOS.cachedPages[d.edition] || new Set()).add(d.num); });

  function dbg(msg) { try { QN.debugLog({ msg: String(msg) }); } catch (e) {} }
  window.addEventListener('error', (e) => dbg('JS error: ' + e.message + ' @' + e.lineno));
  // The page's own state loads asynchronously on iOS; retry until the app is ready to open the mushaf.
  function runShortcut(value, tries) {
    tries = tries || 0;
    whenLoaded(() => {
      const ready = typeof window.openFromShortcut === 'function' && document.getElementById('mushafModal');
      if (!ready) { if (tries < 40) setTimeout(() => runShortcut(value, tries + 1), 250); return; }
      setTimeout(() => {
        try { window.openFromShortcut(value); } catch (e) { dbg('openFromShortcut error ' + e); }
        if (value === 'mushaf') setTimeout(() => {
          const m = document.getElementById('mushafModal');
          if (m && m.classList.contains('hidden') && tries < 40) runShortcut(value, tries + 1);
        }, 1200);
      }, 400);
    });
  }
  function whenLoaded(fn) {
    if (document.readyState === 'complete') fn(); else window.addEventListener('load', fn, { once: true });
  }
  function onResume() {
    QN.consumePendingDone().then((r) => {
      IOS.pendingDone = (r && r.value) || '';
      if (IOS.pendingDone) whenLoaded(() => { if (typeof window.onNativeResume === 'function') window.onNativeResume(); });
    }).catch(() => {});
    QN.getPendingShortcut().then((r) => {
      if (r && r.value) runShortcut(r.value);
    }).catch(() => {});
    QN.audioState().then((s) => {
      if (s && s.active) whenLoaded(() => { if (typeof window.onNativeAudio === 'function') window.onNativeAudio(s); });
    }).catch(() => {});
  }
  QN.addListener('resume', onResume);
  onResume();

  // ---- update notice (iOS apps cannot install their own updates) ----
  function newer(a, b) {
    const pa = String(a).replace(/^v/i, '').split('.').map((n) => parseInt(n, 10) || 0);
    const pb = String(b).replace(/^v/i, '').split('.').map((n) => parseInt(n, 10) || 0);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
      const d = (pa[i] || 0) - (pb[i] || 0);
      if (d !== 0) return d > 0;
    }
    return false;
  }
  function checkUpdates(manual) {
    const last = Number(localStorage.getItem('ios_update_check') || 0);
    if (!manual && Date.now() - last < 30 * 60 * 1000) return;
    fetch(`https://api.github.com/repos/${IOS_REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } })
      .then((r) => (r.ok ? r.json() : null))
      .then((rel) => {
        if (!rel || !rel.tag_name) { if (manual) alert('تعذّر التحقق من التحديثات. تحقق من اتصالك بالإنترنت.'); return; }
        localStorage.setItem('ios_update_check', String(Date.now()));
        const latest = rel.tag_name.replace(/^v/i, '');
        if (newer(latest, IOS.version)) {
          if (confirm(`تحديث جديد متوفر ✨\nالإصدار ${latest} متوفر (لديك ${IOS.version}).\n\nهل تريد فتح صفحة التحميل؟`)) QN.openURL({ url: rel.html_url || RELEASES_PAGE });
        } else if (manual) {
          alert(`أنت تستخدم أحدث إصدار (${IOS.version})`);
        }
      })
      .catch(() => { if (manual) alert('تعذّر التحقق من التحديثات. تحقق من اتصالك بالإنترنت.'); });
  }
  whenLoaded(() => setTimeout(() => checkUpdates(false), 2500));

  // ---- the bridge used by the shared web app ----
  window.AndroidBridge = {
    // widget data / reminders
    updateWidget(surah, detail) { QN.setWird({ surah, detail }); },
    scheduleReminders(time1, enabled2, time2) { QN.scheduleReminders({ time1, enabled2: !!enabled2, time2 }); },
    setWirdStatus(key, doneDate) { QN.setWirdStatus({ key, doneDate: doneDate || '' }); },
    consumePendingDone() { const v = IOS.pendingDone; IOS.pendingDone = ''; return v; },
    testNotification() { QN.testNotification(); },

    // screen
    setKeepScreenOn(on) { QN.setKeepScreenOn({ on: !!on }); },
    setDarkMode(dark) { QN.setDarkMode({ dark: !!dark }); },

    // backup / share / feedback
    saveBackup(json, fileName) {
      QN.saveBackup({ json, fileName }).then((r) => { if (typeof window.onNativeBackupSaved === 'function') window.onNativeBackupSaved(!!(r && r.ok)); });
    },
    autoBackup(json) { QN.autoBackup({ json }).then(refreshBackupInfo); },
    autoBackupInfo() { return JSON.stringify(IOS.backupInfo); },
    shareApp() {
      QN.share({ text: 'أسهل نظام لحفظ القرآن — تطبيق لحفظ القرآن الكريم في عامين، بروايتي ورش وحفص، مع التلاوة والتسميع والتذكير اليومي.\n' +
        'نسخة iPhone/iPad: ' + RELEASES_PAGE + '\nنسخة أندرويد: https://github.com/b1770u/ashal-nidam-hifz-quran-apk/releases/latest' });
    },
    openFeedback() {
      const body = `اكتب ملاحظتك هنا:\n\n\n---\nإصدار التطبيق: ${IOS.version} (iOS)\nالجهاز: ${navigator.userAgent}`;
      QN.openURL({ url: `https://github.com/${IOS_REPO}/issues/new?title=${encodeURIComponent('ملاحظة على التطبيق')}&body=${encodeURIComponent(body)}` });
    },

    // version / updates
    getAppVersion() { return IOS.version; },
    checkForUpdates() { checkUpdates(true); },

    // speech
    speechAvailable() { return true; },
    speechStart(lang) { QN.speechStart({ lang: lang || 'ar-SA' }); },
    speechStop() { QN.speechStop(); },

    // bundled text
    getSurahText(riwayah, surah) {
      try {
        const d = loadJSON(riwayah === 'warsh' ? 'quran-warsh.json' : 'quran-hafs.json');
        const arr = d[Number(surah) - 1] || [];
        return JSON.stringify(arr.map((t, i) => ({ verse: i + 1, text: t })));
      } catch (e) { return ''; }
    },
    getPageMap() {
      try { return JSON.stringify(loadJSON('ayah-pages.json')); } catch (e) { return ''; }
    },
    getAyahPage(surah, ayah) {
      try { const p = loadJSON('ayah-pages.json'); return (p[Number(surah) - 1] && p[Number(surah) - 1][Number(ayah) - 1]) || 0; } catch (e) { return 0; }
    },

    // offline downloads
    offlineStatus() { scheduleRefresh(); return JSON.stringify(IOS.offline || EMPTY_STATUS); },
    offlineDownload(kind, key, from, to) {
      if (IOS.offline && IOS.offline.running) return false;
      IOS.offline = Object.assign({}, IOS.offline || EMPTY_STATUS, { running: true });
      QN.offlineDownload({ kind, key, from: Number(from), to: Number(to) }).then((r) => { if (!r || !r.ok) refreshOffline(); });
      return true;
    },
    offlineCancel() { QN.offlineCancel(); },
    offlineClear(what) {
      if (IOS.offline && IOS.offline.running) return false;
      QN.offlineClear({ what }).then(() => {
        Object.keys(IOS.cachedPages).forEach((ed) => IOS.cachedPages[ed].clear());
        refreshOffline();
      });
      IOS.offline = Object.assign({}, EMPTY_STATUS);
      return true;
    },

    // native recitation
    audioAvailable() { return true; },
    getReciters() { return JSON.stringify(RECITERS); },
    audioPlay(json) { QN.audioPlay(JSON.parse(json)); },
    audioStop() { QN.audioStop(); },
    audioToggle() { QN.audioToggle(); },
    audioSetSpeed(speed) { QN.audioSetSpeed({ speed: Number(speed) }); },
    audioSleep(minutes) { QN.audioSleep({ minutes: Number(minutes) }); }
  };
})();

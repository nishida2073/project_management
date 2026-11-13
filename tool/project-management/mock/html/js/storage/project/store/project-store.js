(function () {
  var KEY = 'projectList';

  var SEED = [
    { code: 'PJ-2601', year: '2026年度', sales: 'SL-01', part: 'PT-01', name: 'G新人研修（NTTデータ金融共催）', customer: 'CUS-001', startMonth: '2026/09', pm: 'STF-014', pl: ['STF-021'], memo: '' },
    { code: 'PJ-2602', year: '2026年度', sales: 'SL-02', part: 'PT-01', name: 'ビジネス基礎研修 定期開催', customer: 'CUS-002', startMonth: '2026/09', pm: 'STF-064', pl: ['STF-069'], memo: '' },
    { code: 'PJ-2603', year: '2026年度', sales: 'SL-01', part: 'PT-01', name: '次世代リーダー育成プログラム', customer: 'CUS-003', startMonth: '2026/10', pm: 'STF-065', pl: ['STF-070', 'STF-073'], memo: '' },
    { code: 'PJ-2604', year: '2026年度', sales: 'SL-01', part: 'PT-02', name: 'グローバル基礎コース 公募', customer: '', startMonth: '2026/09', pm: 'STF-066', pl: ['STF-070'], memo: '' },
    { code: 'PJ-2605', year: '2026年度', sales: 'SL-01', part: 'PT-01', name: 'マネジメント基礎研修', customer: 'CUS-004', startMonth: '2026/10', pm: 'STF-067', pl: ['STF-071'], memo: '' },
    { code: 'PJ-2606', year: '2026年度', sales: 'SL-01', part: 'PT-01', name: 'システム基盤実践研修', customer: 'CUS-005', startMonth: '2026/09', pm: 'STF-014', pl: ['STF-022'], memo: '' },
    { code: 'PJ-2607', year: '2026年度', sales: 'SL-02', part: 'PT-01', name: '新人フォローアップ研修', customer: 'CUS-006', startMonth: '2026/11', pm: 'STF-045', pl: ['STF-072'], memo: '' }
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED));
    save(seed);
    return seed;
  }

  function nextCode(list) {
    var max = 0;
    list.forEach(function (p) {
      var n = parseInt(String(p.code).replace('PJ-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'PJ-' + String(max + 1).padStart(4, '0');
  }

  function map() {
    var out = {};
    load().forEach(function (p) {
      out[p.code] = { name: p.name, sales: p.sales, part: p.part, customer: p.customer };
    });
    return out;
  }

  window.ProjectStore = { load: load, save: save, nextCode: nextCode, map: map };
})();

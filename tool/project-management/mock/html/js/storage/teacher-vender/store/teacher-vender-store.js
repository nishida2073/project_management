(function () {
  var KEY = 'teacherVenderList';

  var SEED = [
    { code: 'TCV-001', name: '株式会社NEUトレーニング', contract: 'CT-01', years: ['2025', '2026'], tel: '03-1234-5678', address: '東京都千代田区〇〇1-2-3', memo: 'ビジネス基礎研修を主に担当', contactName: '佐々木　小次郎', contactEmail: 'sasaki@neu-training.co.jp', status: OperatingStatusStore.labelOf('ACTIVE') },
    { code: 'TCV-002', name: '株式会社NDUパートナーズ', contract: 'CT-01', years: ['2026'], tel: '03-2345-6789', address: '', memo: '公募コース全般', contactName: '木下', contactEmail: '', status: OperatingStatusStore.labelOf('ACTIVE') },
    { code: 'TCV-003', name: '株式会社ユニバ研修サービス', contract: 'CT-01', years: ['2025'], tel: '06-3456-7890', address: '', memo: '大阪拠点対応可', contactName: '江口', contactEmail: '', status: OperatingStatusStore.labelOf('ACTIVE') },
    { code: 'TCV-004', name: '株式会社CECトラスト', contract: 'CT-02', years: ['2025'], tel: '03-4567-8901', address: '', memo: 'マネジメント研修専門', contactName: '森', contactEmail: '', status: OperatingStatusStore.labelOf('ACTIVE') },
    { code: 'TCV-005', name: '株式会社アムネット', contract: 'CT-01', years: ['2024'], tel: '03-5678-9012', address: '', memo: '教材発注のみ', contactName: '川口', contactEmail: '', status: OperatingStatusStore.labelOf('STOPPED') }
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
    list.forEach(function (v) {
      var n = parseInt(String(v.code).replace('TCV-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'TCV-' + String(max + 1).padStart(3, '0');
  }

  function activeNames() {
    return load().filter(function (v) { return v.status !== OperatingStatusStore.labelOf('STOPPED'); }).map(function (v) { return v.name; });
  }

  var INTERNAL = 'INTERNAL';

  function nameOf(code) {
    if (code === INTERNAL) return '社内';
    var found = load().filter(function (v) { return v.code === code; })[0];
    return found ? found.name : '';
  }

  function codeOf(name) {
    if (name === '社内') return INTERNAL;
    var found = load().filter(function (v) { return v.name === name; })[0];
    return found ? found.code : '';
  }

  window.TeacherVenderStore = { load: load, save: save, nextCode: nextCode, activeNames: activeNames, nameOf: nameOf, codeOf: codeOf, INTERNAL: INTERNAL };
})();

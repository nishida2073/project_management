(function () {
  var KEY = 'staffVenderList';

  var SEED = [
    { code: 'STV-001', name: '株式会社あおぞら研修', tel: '03-1000-0001', address: '東京都千代田区丸の内1-1-1', memo: '新人研修を中心に担当', contactName: '青木 大輔', contactEmail: 'aoki@aozora-training.example.jp', status: '稼働中' },
    { code: 'STV-002', name: '合同会社さくら人材', tel: '03-1000-0002', address: '東京都港区六本木2-2-2', memo: 'キャリア研修の講師派遣', contactName: '桜井 美咲', contactEmail: 'sakurai@sakura-jinzai.example.jp', status: '稼働中' },
    { code: 'STV-003', name: '株式会社ひまわりキャリア', tel: '06-1000-0003', address: '大阪府大阪市北区梅田3-3-3', memo: '大阪拠点の対応可', contactName: '向井 健太', contactEmail: 'mukai@himawari-career.example.jp', status: '稼働中' },
    { code: 'STV-004', name: '株式会社みらい教育', tel: '03-1000-0004', address: '東京都渋谷区道玄坂4-4-4', memo: 'マネジメント研修専門', contactName: '緑川 恵', contactEmail: 'midorikawa@mirai-kyoiku.example.jp', status: '稼働中' }
  ];

  var INTERNAL = 'INTERNAL';

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

  function find(code) {
    return load().filter(function (c) { return c.code === code; })[0];
  }

  function nameOf(code) {
    if (code === INTERNAL) return '社内';
    var found = find(code);
    return found ? found.name : '';
  }

  function codeOf(name) {
    if (name === '社内') return INTERNAL;
    var found = load().filter(function (c) { return c.name === name; })[0];
    return found ? found.code : '';
  }

  function activeNames() {
    return load().filter(function (c) { return c.status !== '停止中'; }).map(function (c) { return c.name; });
  }

  function nextCode(list) {
    var max = 0;
    list.forEach(function (c) {
      var n = parseInt(String(c.code).replace('STV-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'STV-' + String(max + 1).padStart(3, '0');
  }

  window.StaffVenderStore = { load: load, save: save, find: find, nameOf: nameOf, codeOf: codeOf, activeNames: activeNames, nextCode: nextCode, INTERNAL: INTERNAL };
})();

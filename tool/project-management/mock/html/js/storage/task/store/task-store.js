(function () {
  var KEY = 'taskList';
  var SEED = [
    { id: 'TSK-001', name: 'クラス登録', kinds: ['TK-01'], order: 1, company: 'INTERNAL', days: -10, workType: 'WT-01' },
    { id: 'TSK-002', name: '名簿受領督促', kinds: ['TK-02'], order: 1, company: 'STV-004', days: -7, workType: 'WT-01' },
    { id: 'TSK-003', name: '講師契約', kinds: ['TK-02'], order: 2, company: 'STV-001', days: -14, workType: 'WT-01' },
    { id: 'TSK-004', name: '受講者登録(OliveOne)', kinds: ['TK-01'], order: 2, company: 'INTERNAL', days: -5, workType: 'WT-01' },
    { id: 'TSK-005', name: '受講詳細案内発出', kinds: ['TK-02'], order: 3, company: 'STV-001', days: -3, workType: 'WT-01' },
    { id: 'TSK-006', name: '電子教材送付', kinds: ['TK-02'], order: 4, company: 'STV-002', days: -2, workType: 'WT-01' },
    { id: 'TSK-007', name: '出欠確認・報告', kinds: ['TK-02'], order: 5, company: 'STV-003', days: -1, workType: 'WT-01' },
    { id: 'TSK-008', name: 'アンケート実施案内', kinds: ['TK-02'], order: 6, company: 'STV-002', days: 6, workType: 'WT-02' },
    { id: 'TSK-009', name: 'テスト結果集計', kinds: ['TK-01'], order: 3, company: 'STV-003', days: 7, workType: 'WT-02' },
    { id: 'TSK-010', name: 'アンケート集計・格納', kinds: ['TK-01'], order: 4, company: 'INTERNAL', days: 8, workType: 'WT-02' },
    { id: 'TSK-011', name: '報告書作成', kinds: ['TK-01'], order: 5, company: 'INTERNAL', days: 5, workType: 'WT-02' },
    { id: 'TSK-012', name: '再テストリマインド', kinds: ['TK-02'], order: 7, company: 'STV-001', days: 9, workType: 'WT-02' },
    { id: 'TSK-013', name: '受講者データ作成', kinds: ['TK-01'], order: 6, company: 'STV-002', days: 10, workType: 'WT-02' },
    { id: 'TSK-014', name: '成績データ集計', kinds: ['TK-01'], order: 8, company: 'INTERNAL', days: 11, workType: 'WT-03' },
    { id: 'TSK-015', name: '受講実績データ登録', kinds: ['TK-01'], order: 7, company: 'INTERNAL', days: 12, workType: 'WT-02' },
    { id: 'TSK-016', name: '案内メール送付', kinds: ['TK-02'], order: 8, company: 'STV-003', days: 13, workType: 'WT-02' },
    { id: 'TSK-017', name: '会場手配', kinds: ['TK-02'], order: 9, company: 'STV-004', days: 14, workType: 'WT-03' },
    { id: 'TSK-018', name: '当日運営スタッフ手配', kinds: ['TK-02'], order: 10, company: 'INTERNAL', days: 15, workType: 'WT-03' }
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

  function nextId(list) {
    var max = 0;
    list.forEach(function (t) {
      var n = parseInt(String(t.id).replace('TSK-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'TSK-' + String(max + 1).padStart(3, '0');
  }

  window.TaskStore = { load: load, save: save, nextId: nextId };
})();

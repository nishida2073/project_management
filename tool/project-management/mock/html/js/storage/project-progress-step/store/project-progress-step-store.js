(function () {
  var SEED = [
    { code: 'PPS-01', order: 1, name: '案件受付', days: 0 },
    { code: 'PPS-02', order: 2, name: '見積作成', days: 10 },
    { code: 'PPS-03', order: 3, name: '見積提出', days: 15 },
    { code: 'PPS-04', order: 4, name: '受注確定', days: 19 },
    { code: 'PPS-05', order: 5, name: '社内承認', days: 25 },
    { code: 'PPS-06', order: 6, name: '教材準備', days: 30 },
    { code: 'PPS-07', order: 7, name: '講師手配', days: 32 },
    { code: 'PPS-08', order: 8, name: '顧客契約締結', days: 39 },
    { code: 'PPS-09', order: 9, name: '開発実施準備', days: 46 },
    { code: 'PPS-10', order: 10, name: '研修実施', days: 57 },
    { code: 'PPS-11', order: 11, name: 'アンケート集計', days: 72 },
    { code: 'PPS-12', order: 12, name: '検収', days: 92 },
    { code: 'PPS-13', order: 13, name: '請求・完了報告', days: 107 }
  ];

  function pad(n) { return ('0' + n).slice(-2); }

  function sortByOrder() {
    return SEED.slice().sort(function (a, b) { return a.order - b.order; });
  }

  function load() {
    return sortByOrder().map(function (t) {
      return { code: t.code, order: t.order, name: t.name, days: t.days };
    });
  }

  function names() {
    return sortByOrder().map(function (t) { return t.name; });
  }

  function planOf(startMonth, index) {
    var m = String(startMonth || '').split('/');
    var t = sortByOrder()[index];
    if (m.length < 2 || !t) return '';
    var d = new Date(Number(m[0]), Number(m[1]) - 1, 1 + t.days);
    return d.getFullYear() + '/' + pad(d.getMonth() + 1) + '/' + pad(d.getDate());
  }

  window.ProjectProgressStepStore = { load: load, names: names, planOf: planOf };
})();

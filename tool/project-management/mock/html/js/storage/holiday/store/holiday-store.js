(function () {
  var KEY = 'holidayList';

  var SEED = [
    { date: '2026/01/01', name: '元日', type: '祝日' },
    { date: '2026/01/12', name: '成人の日', type: '祝日' },
    { date: '2026/02/11', name: '建国記念の日', type: '祝日' },
    { date: '2026/02/23', name: '天皇誕生日', type: '祝日' },
    { date: '2026/03/20', name: '春分の日', type: '祝日' },
    { date: '2026/04/29', name: '昭和の日', type: '祝日' },
    { date: '2026/05/03', name: '憲法記念日', type: '祝日' },
    { date: '2026/05/04', name: 'みどりの日', type: '祝日' },
    { date: '2026/05/05', name: 'こどもの日', type: '祝日' },
    { date: '2026/05/06', name: '振替休日', type: '祝日' },
    { date: '2026/07/20', name: '海の日', type: '祝日' },
    { date: '2026/08/11', name: '山の日', type: '祝日' },
    { date: '2026/09/21', name: '敬老の日', type: '祝日' },
    { date: '2026/09/22', name: '国民の休日', type: '祝日' },
    { date: '2026/09/23', name: '秋分の日', type: '祝日' },
    { date: '2026/10/12', name: 'スポーツの日', type: '祝日' },
    { date: '2026/11/03', name: '文化の日', type: '祝日' },
    { date: '2026/11/23', name: '勤労感謝の日', type: '祝日' }
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

  function add(date, name, type) {
    var list = load();
    if (list.some(function (h) { return h.date === date; })) return false;
    list.push({ date: date, name: name || '', type: type || '休業日' });
    list.sort(function (a, b) { return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0); });
    save(list);
    return true;
  }

  function remove(date) {
    save(load().filter(function (h) { return h.date !== date; }));
  }

  function isHoliday(date) {
    return load().some(function (h) { return h.date === date; });
  }

  window.HolidayStore = { load: load, save: save, add: add, remove: remove, isHoliday: isHoliday };
})();

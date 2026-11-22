(function () {
  var KEY = 'requestHistoryList';

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    return [];
  }

  function nextId(list) {
    var max = 0;
    list.forEach(function (r) {
      var n = parseInt(String(r.id).replace('REQ-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'REQ-' + String(max + 1).padStart(3, '0');
  }

  function now() {
    var d = new Date();
    return fmtDate(d) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  function add(rec) {
    var list = load();
    rec.id = nextId(list);
    rec.reissues = [];
    list.push(rec);
    save(list);
    return rec;
  }

  function addReissue(id) {
    var list = load();
    list.forEach(function (r) { if (r.id === id) r.reissues.push(now()); });
    save(list);
  }

  window.RequestHistoryStore = { load: load, add: add, addReissue: addReissue, now: now };
})();

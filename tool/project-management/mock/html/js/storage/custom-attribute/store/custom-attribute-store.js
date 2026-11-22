(function () {
  var KEY = 'customAttributeList';

  var TYPES = { text: '文字', number: '数字', date: '日付', select: '選択' };
  var TARGETS = { class: 'クラス', vendorAssign: '登壇依頼' };

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

  function nextCode(list) {
    var max = 0;
    list.forEach(function (a) {
      var n = parseInt(String(a.code).replace('AT-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'AT-' + String(max + 1).padStart(3, '0');
  }

  function add(def) {
    var list = load();
    def.code = nextCode(list);
    list.push(def);
    save(list);
    return def;
  }

  function update(code, changes) {
    var list = load();
    list.forEach(function (a) { if (a.code === code) Object.assign(a, changes); });
    save(list);
  }

  function remove(code) {
    save(load().filter(function (a) { return a.code !== code; }));
  }

  function forTarget(target) {
    return load().filter(function (a) { return a.target === target; });
  }

  window.CustomAttributeStore = { load: load, add: add, update: update, remove: remove, forTarget: forTarget, TYPES: TYPES, TARGETS: TARGETS };
})();

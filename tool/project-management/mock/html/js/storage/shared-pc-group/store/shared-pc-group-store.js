(function () {
  var KEY = 'sharedPcGroupList';

  var SEED = [
    { code: 'SPG-001', name: 'グループA', pcCount: 20, status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'SPG-002', name: 'グループB', pcCount: 30, status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'SPG-003', name: 'グループC', pcCount: 15, status: OperatingStatusStore.nameOf('ACTIVE') }
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
    list.forEach(function (g) {
      var n = parseInt(String(g.code).replace('SPG-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'SPG-' + String(max + 1).padStart(3, '0');
  }

  function names() {
    return load().filter(function (g) { return g.status === OperatingStatusStore.nameOf('ACTIVE'); }).map(function (g) { return g.name; });
  }

  function nameOf(code) {
    var found = load().filter(function (g) { return g.code === code; })[0];
    return found ? found.name : '';
  }

  function pcCountOf(code) {
    var found = load().filter(function (g) { return g.code === code; })[0];
    return found ? found.pcCount : '';
  }

  function codeOf(name) {
    var found = load().filter(function (g) { return g.name === name; })[0];
    return found ? found.code : '';
  }

  window.SharedPcGroupStore = {
    load: load,
    save: save,
    nextCode: nextCode,
    names: names,
    nameOf: nameOf,
    codeOf: codeOf,
    pcCountOf: pcCountOf
  };
})();

(function () {
  var LIST = [
    { code: 'WAIT', name: '未着手', color: 'gray' },
    { code: 'PROGRESS', name: '進行中', color: 'blue' },
    { code: 'DONE', name: '完了', color: 'green' },
    { code: 'DELAY', name: '遅延', color: 'red' }
  ];

  function load() {
    return LIST.map(function (s) { return { code: s.code, name: s.name, color: s.color }; });
  }

  function find(code) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].code === code) return LIST[i];
    return null;
  }

  function nameOf(code) {
    var s = find(code);
    return s ? s.name : '';
  }

  function colorOf(code) {
    var s = find(code);
    return s ? s.color : '';
  }

  function codes() {
    return LIST.map(function (s) { return s.code; });
  }

  function options() {
    return LIST.map(function (s) { return s.name; }).join(',');
  }

  function byName() {
    var map = {};
    LIST.forEach(function (s) { map[s.name] = s.code; });
    return map;
  }

  function nameByCode() {
    var map = {};
    LIST.forEach(function (s) { map[s.code] = s.name; });
    return map;
  }

  function colorByCode() {
    var map = {};
    LIST.forEach(function (s) { map[s.code] = s.color; });
    return map;
  }

  function fillDom() {
    document.querySelectorAll('[data-task-progress-name]').forEach(function (el) {
      if (!el.textContent) el.textContent = nameOf(el.getAttribute('data-task-progress-name'));
    });
    document.querySelectorAll('[data-task-progress-options]').forEach(function (el) {
      el.setAttribute('data-options', 'すべて,' + options());
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.TaskProgressStore = {
    load: load, LIST: LIST, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes,
    options: options, byName: byName, nameByCode: nameByCode, colorByCode: colorByCode
  };
})();

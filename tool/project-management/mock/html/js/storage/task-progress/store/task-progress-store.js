(function () {
  var LIST = [
    { key: 'WAIT', label: '未着手', color: 'gray' },
    { key: 'PROGRESS', label: '進行中', color: 'blue' },
    { key: 'DONE', label: '完了', color: 'green' },
    { key: 'DELAY', label: '遅延', color: 'red' }
  ];

  function byKey(key) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].key === key) return LIST[i];
    return null;
  }

  function labelOf(key) {
    var s = byKey(key);
    return s ? s.label : '';
  }

  function colorOf(key) {
    var s = byKey(key);
    return s ? s.color : '';
  }

  function options() {
    return LIST.map(function (s) { return s.label; }).join(',');
  }

  function byLabel() {
    var map = {};
    LIST.forEach(function (s) { map[s.label] = s.key; });
    return map;
  }

  function labelByKey() {
    var map = {};
    LIST.forEach(function (s) { map[s.key] = s.label; });
    return map;
  }

  function colorByKey() {
    var map = {};
    LIST.forEach(function (s) { map[s.key] = s.color; });
    return map;
  }

  function fillDom() {
    document.querySelectorAll('[data-task-progress-label]').forEach(function (el) {
      if (!el.textContent) el.textContent = labelOf(el.getAttribute('data-task-progress-label'));
    });
    document.querySelectorAll('[data-task-progress-options]').forEach(function (el) {
      el.setAttribute('data-options', 'すべて,' + options());
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.TaskProgressStore = {
    LIST: LIST, labelOf: labelOf, colorOf: colorOf, options: options,
    byLabel: byLabel, labelByKey: labelByKey, colorByKey: colorByKey
  };
})();

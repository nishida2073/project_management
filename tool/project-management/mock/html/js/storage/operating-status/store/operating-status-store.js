(function () {
  var LIST = [
    { code: 'ACTIVE', name: '稼働中', color: 'green' },
    { code: 'STOPPED', name: '停止中', color: 'gray' }
  ];

  var STATUS = {};
  LIST.forEach(function (s) { STATUS[s.code] = { code: s.code, name: s.name, color: s.color }; });

  function load() {
    return LIST.map(function (s) { return { code: s.code, name: s.name, color: s.color }; });
  }

  function find(code) {
    return STATUS[code];
  }

  function nameOf(code) {
    var found = find(code);
    return found ? found.name : '';
  }

  function colorOf(code) {
    var found = find(code);
    return found ? found.color : '';
  }

  function codes() {
    return LIST.map(function (s) { return s.code; });
  }

  function tag(s, style, cls) {
    return '<span class="tag ' + (cls ? cls + ' ' : '') + s.color + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.name + '</span>';
  }

  function options() {
    return LIST.map(function (s) { return s.name; }).join(',');
  }

  function fillDom() {
    document.querySelectorAll('[data-status]').forEach(function (el) {
      if (!el.textContent) el.textContent = nameOf(el.getAttribute('data-status'));
    });
    document.querySelectorAll('[data-status-options]').forEach(function (el) {
      el.setAttribute('data-options', 'すべて,' + options());
    });
    document.querySelectorAll('[data-status-toggle]').forEach(function (el) {
      el.setAttribute('data-on', nameOf('ACTIVE'));
      el.setAttribute('data-off', nameOf('STOPPED'));
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.OperatingStatusStore = { load: load, STATUS: STATUS, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, options: options, tag: tag };
})();

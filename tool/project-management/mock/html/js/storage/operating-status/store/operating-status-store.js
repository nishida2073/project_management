(function () {
  var LIST = [
    { key: 'ACTIVE', label: '稼働中', color: 'green' },
    { key: 'STOPPED', label: '停止中', color: 'gray' }
  ];

  var STATUS = {};
  LIST.forEach(function (s) { STATUS[s.key] = { label: s.label, tag: s.color }; });

  function find(key) {
    return STATUS[key];
  }

  function labelOf(key) {
    var found = find(key);
    return found ? found.label : '';
  }

  function colorOf(key) {
    var found = find(key);
    return found ? found.tag : '';
  }

  function tag(s, style, cls) {
    return '<span class="tag ' + (cls ? cls + ' ' : '') + s.tag + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.label + '</span>';
  }

  function fillDom() {
    document.querySelectorAll('[data-status]').forEach(function (el) {
      if (!el.textContent) el.textContent = labelOf(el.getAttribute('data-status'));
    });
    document.querySelectorAll('[data-status-options]').forEach(function (el) {
      el.setAttribute('data-options', ['すべて'].concat(LIST.map(function (s) { return s.label; })).join(','));
    });
    document.querySelectorAll('[data-status-toggle]').forEach(function (el) {
      el.setAttribute('data-on', labelOf('ACTIVE'));
      el.setAttribute('data-off', labelOf('STOPPED'));
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fillDom);
  else fillDom();

  window.OperatingStatusStore = { STATUS: STATUS, find: find, labelOf: labelOf, colorOf: colorOf, tag: tag };
})();

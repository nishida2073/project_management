(function () {
  var LIST = [
    { key: 'REQUESTED', label: '依頼済', color: 'green' },
    { key: 'REQUESTING', label: '依頼中', color: 'blue' },
    { key: 'BEFORE', label: '依頼前', color: 'orange' },
    { key: 'OPEN', label: '空き枠', color: 'gray' },
    { key: 'OUT_OF_PLAN', label: '予定外', color: 'red' }
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

  function options(keys) {
    return keys.map(labelOf).join(',');
  }

  function fillDom() {
    document.querySelectorAll('[data-slot-options]').forEach(function (el) {
      el.setAttribute('data-options', options(el.getAttribute('data-slot-options').split(',')));
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.SlotStatusStore = { STATUS: STATUS, find: find, labelOf: labelOf, colorOf: colorOf, options: options, tag: tag };
})();

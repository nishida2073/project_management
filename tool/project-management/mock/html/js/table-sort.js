(function () {
  var DATE_RE = /^(\d{4})\/(\d{1,2})\/(\d{1,2})$/;
  var NUM_RE = /^-?\d+(\.\d+)?/;

  function textOf(td) {
    return td ? td.textContent.replace(/\s+/g, ' ').trim() : '';
  }

  function keyOf(text) {
    if (!text || text === '-') return { empty: true };
    var d = DATE_RE.exec(text);
    if (d) return { type: 0, value: new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3])).getTime() };
    var n = NUM_RE.exec(text);
    if (n) return { type: 1, value: parseFloat(n[0]), text: text };
    return { type: 2, text: text };
  }

  function compare(a, b) {
    var ka = keyOf(a), kb = keyOf(b);
    if (ka.empty || kb.empty) return (ka.empty ? 1 : 0) - (kb.empty ? 1 : 0);
    if (ka.type !== kb.type) return ka.type - kb.type;
    if (ka.type === 2) return ka.text.localeCompare(kb.text, 'ja');
    if (ka.type === 1 && ka.value !== kb.value) return ka.value - kb.value;
    if (ka.type === 1) return (ka.text || '').localeCompare(kb.text || '', 'ja');
    return ka.value - kb.value;
  }

  function init() {
    var table = document.querySelector('.table-card table');
    if (!table) return;
    var tbody = table.querySelector('tbody');
    var heads = table.querySelectorAll('thead tr:last-child th');
    if (!tbody || !heads.length) return;

    var state = { index: -1, dir: 0 };

    Array.prototype.forEach.call(heads, function (th) {
      var label = th.textContent.trim();
      if (!label || label === '操作' || th.classList.contains('no-sort')) return;
      th.classList.add('sortable');
      th.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('.col-resize')) return;
        sortBy(th);
      });
    });

    function sortBy(th) {
      var index = th.cellIndex;
      var dir = (state.index === index && state.dir === 1) ? -1 : 1;
      state.index = index;
      state.dir = dir;

      var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
      rows.sort(function (ra, rb) {
        var r = compare(textOf(ra.cells[index]), textOf(rb.cells[index]));
        return r * dir;
      });
      rows.forEach(function (tr) { tbody.appendChild(tr); });

      Array.prototype.forEach.call(heads, function (h) {
        h.classList.remove('sort-asc', 'sort-desc');
      });
      th.classList.add(dir === 1 ? 'sort-asc' : 'sort-desc');

      if (window.listPaginate) window.listPaginate(true);
    }
  }

  init();
})();

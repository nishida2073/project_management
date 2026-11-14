(function () {
  var last = {};
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; }).map(function (n) { return n.textContent; }).join('').trim();
  }
  function norm(v) { return v === 'すべて' || v === '選択してください' ? '' : v; }
  function collect() {
    var items = [];
    document.querySelectorAll('.filter-panel .js-select').forEach(function (el, i) {
      items.push({ key: 'sel' + i, el: el, value: norm(ownText(el)), select: true });
    });
    var vendor = document.getElementById('requestVendor');
    if (vendor) items.push({ key: 'vendor', el: vendor, value: norm(ownText(vendor)), select: true });
    document.querySelectorAll('.filter-panel .js-date').forEach(function (el, i) {
      items.push({ key: 'date' + i, el: el, value: ownText(el) });
    });
    document.querySelectorAll('.filter-panel .js-month').forEach(function (el, i) {
      items.push({ key: 'month' + i, el: el, value: ownText(el) });
    });
    return items;
  }
  function snapshot() {
    collect().forEach(function (it) { last[it.key] = it.value; });
  }
  function apply() {
    var searchNeeded = false;
    var layoutNeeded = false;
    collect().forEach(function (it) {
      var prev = last[it.key] === undefined ? '' : last[it.key];
      if (prev === it.value) return;
      last[it.key] = it.value;
      searchNeeded = true;
      var cls = it.select ? it.el.getAttribute('data-hide-class') : null;
      if (!cls) return;
      layoutNeeded = true;
      document.querySelectorAll('table .' + cls).forEach(function (cell) { cell.style.display = it.value ? 'none' : ''; });
    });
    if (layoutNeeded) {
      var body = document.querySelector('table tbody');
      var first = body && body.firstElementChild;
      if (first) {
        var next = first.nextSibling;
        body.removeChild(first);
        body.insertBefore(first, next);
      }
    }
    if (!searchNeeded) return;
    var search = document.querySelector('.filter-panel .search-btn');
    if (search) setTimeout(function () { search.click(); }, 0);
  }
  snapshot();
  window.applyColumnFilters = apply;
  document.addEventListener('click', function () { setTimeout(apply, 0); }, true);
})();

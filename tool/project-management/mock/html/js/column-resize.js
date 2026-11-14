(function () {
  var MIN = 5;
  var YEAR_MIN = 90;

  function sumWidths(list) {
    return list.reduce(function (a, th) { return a + th.getBoundingClientRect().width; }, 0);
  }

  function initTable(table) {
    var thead = table.querySelector('thead');
    var tbody = table.querySelector('tbody');
    if (!thead || !tbody) return;
    var allHeads = Array.prototype.slice.call(thead.querySelectorAll('tr th'));
    if (!allHeads.length) return;
    var heads = Array.prototype.slice.call(thead.querySelectorAll('tr th.sticky'));
    var fixed = false;
    var touched = false;

    function updateTableWidth() {
      var box = table.parentNode.clientWidth - 1;
      var total = Math.floor(sumWidths(allHeads));
      var fill = allHeads.filter(function (t) { return t.classList.contains('fill'); })[0];
      if (fill && box > total) {
        fill.style.width = (Math.floor(fill.getBoundingClientRect().width) + box - total) + 'px';
        total = Math.floor(sumWidths(allHeads));
      }
      table.style.width = total + 'px';
    }

    function fixLayout() {
      if (fixed || !tbody.querySelector('tr')) return;
      fixed = true;
      var yearIdx = -1;
      allHeads.forEach(function (th, i) { if (yearIdx < 0 && th.textContent.trim() === '年度') yearIdx = i; });
      allHeads.forEach(function (th, i) {
        var w = th.getBoundingClientRect().width;
        tbody.querySelectorAll('tr').forEach(function (tr) {
          if (tr.style.display === 'none') return;
          var td = tr.children[i];
          if (td) w = Math.max(w, td.getBoundingClientRect().width);
        });
        if (i === yearIdx) w = Math.max(w, YEAR_MIN);
        th.style.width = w + 'px';
        if (th.textContent.trim() === '操作' || th.classList.contains('no-resize')) th.style.minWidth = th.style.maxWidth = w + 'px';
      });
      table.style.tableLayout = 'fixed';
      updateTableWidth();
    }

    function layout() {
      fixLayout();
      if (heads.length) {
        var lefts = [];
        var acc = 0;
        heads.forEach(function (th, i) {
          lefts[i] = acc;
          th.style.left = acc + 'px';
          acc += th.getBoundingClientRect().width;
        });
        tbody.querySelectorAll('tr').forEach(function (tr) {
          for (var i = 0; i < heads.length; i++) {
            var td = tr.children[i];
            if (td) td.style.left = lefts[i] + 'px';
          }
        });
      }
      updateTableWidth();
    }

    allHeads.forEach(function (th, idx) {
      if (th.textContent.trim() === '操作' || th.classList.contains('no-resize')) return;
      var h = document.createElement('div');
      h.className = 'col-resize';
      th.appendChild(h);
      h.addEventListener('mousedown', function (e) {
        touched = true;
        e.preventDefault();
        var startX = e.clientX;
        var leftHeads = allHeads.slice(0, idx + 1);
        var onlySticky = leftHeads.every(function (t) { return t.classList.contains('sticky'); });
        var group = e.shiftKey || onlySticky ? leftHeads : [th];
        var startWs = group.map(function (g) { return g.getBoundingClientRect().width; });
        var startTotal = startWs.reduce(function (a, b) { return a + b; }, 0);
        var startTable = sumWidths(allHeads);
        var touchesSticky = group.some(function (g) { return g.classList.contains('sticky'); });

        function move(ev) {
          var minStart = Math.min.apply(null, startWs);
          var target = Math.max(startTotal * MIN / minStart, startTotal + ev.clientX - startX);
          var f = target / startTotal;
          group.forEach(function (g, j) {
            var w = (startWs[j] * f) + 'px';
            g.style.whiteSpace = 'normal';
            g.style.width = g.style.minWidth = g.style.maxWidth = w;
          });
          if (touchesSticky) {
            var others = allHeads.filter(function (t) {
              return !t.classList.contains('sticky') && group.indexOf(t) < 0 && t.textContent.trim() !== '操作' && !t.classList.contains('no-resize');
            });
            if (others.length) {
              var lastTh = others[others.length - 1];
              var diff = startTable - sumWidths(allHeads);
              lastTh.style.width = (lastTh.getBoundingClientRect().width + diff) + 'px';
            }
          }
          layout();
        }

        function up() {
          document.removeEventListener('mousemove', move);
          document.removeEventListener('mouseup', up);
        }

        document.addEventListener('mousemove', move);
        document.addEventListener('mouseup', up);
      });
    });

    allHeads.forEach(function (th, i) { th.style.zIndex = String(i === allHeads.length - 1 ? allHeads.length + 1 : allHeads.length - i); });
    new MutationObserver(layout).observe(tbody, { childList: true });
    function refit() {
      if (touched) return;
      allHeads.forEach(function (th) { th.style.width = ''; });
      table.style.tableLayout = '';
      table.style.width = '';
      fixed = false;
      layout();
    }
    new MutationObserver(function (ms) {
      if (ms.some(function (m) { return m.target.tagName === 'TR'; })) refit();
    }).observe(tbody, { attributes: true, attributeFilter: ['style'], subtree: true });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(refit);
    layout();
  }

  Array.prototype.slice.call(document.querySelectorAll('.table-scroll table, .scroll-outer table'))
    
    .forEach(initTable);
})();

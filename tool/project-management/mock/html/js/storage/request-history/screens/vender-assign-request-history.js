(function () {
  var box = $('historyList');
  var list = RequestHistoryStore.load().sort(function (a, b) {
    return parseInt(a.id.replace('REQ-', ''), 10) - parseInt(b.id.replace('REQ-', ''), 10);
  });

  if (!list.length) {
    box.textContent = '依頼履歴はありません';
    return;
  }

  var vendorSel = $('vendorFilter');
  vendorSel.setAttribute('data-options', TeacherVenderStore.activeNames().join(','));
  function applyFilter() {
    var v = placeholderToEmpty(ownText(vendorSel));
    if (v === 'すべて') v = '';
    box.querySelectorAll('[data-vendor]').forEach(function (g) {
      g.style.display = (!v || g.getAttribute('data-vendor') === v) ? '' : 'none';
    });
  }
  $('searchBtn').addEventListener('click', applyFilter);

  list.forEach(function (h) {
    var dayIdx = h.snapshot.header.indexOf('日数');
    var group = document.createElement('div');
    group.className = 'table-card';
    group.setAttribute('data-vendor', h.vendor);
    group.innerHTML =
      '<div class="table-meta">' +
        '<div class="meta-left">' +
          '<div>依頼日時：<b>' + esc(h.issuedAt) + '</b></div>' +
          '<div>講師ベンダー：<b>' + esc(h.vendor) + '</b></div>' +
        '</div>' +
        '<div class="btn primary reissue-btn">再発行</div>' +
      '</div>' +
      '<div class="table-scroll"><table><thead><tr>' +
        h.snapshot.header.map(function (x) { return '<th>' + esc(x) + '</th>'; }).join('') +
      '</tr></thead><tbody>' +
        h.snapshot.rows.map(function (r) {
          return '<tr>' + r.line.map(function (v, i) {
            var unit = (i === dayIdx && v !== '') ? '日' : '';
            return '<td>' + esc(v) + unit + '</td>';
          }).join('') + '</tr>';
        }).join('') +
      '</tbody></table></div>';
    group.querySelector('.reissue-btn').addEventListener('click', function () {
      VenderSheet.save(h.snapshot);
      RequestHistoryStore.addReissue(h.id);
    });
    box.appendChild(group);
  });
})();

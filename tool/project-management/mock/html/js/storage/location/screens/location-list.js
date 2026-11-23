(function () {
  var TYPE_CLASS = {};
  LocationTypeStore.load().forEach(function (t) { TYPE_CLASS[t.code] = t.color; });

  var body = document.getElementById('locationBody');
  var list = LocationStore.load();

  list.forEach(function (l) {
    var on = l.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(l.code) + '</td>' +
      '<td><span class="tag location-type-tag ' + (TYPE_CLASS[l.type] || '') + '">' + esc(LocationTypeStore.nameOf(l.type)) + '</span></td>' +
      '<td>' + esc(l.name) + '</td>' +
      '<td>' + esc(l.tel) + '</td>' +
      '<td>' + esc(l.address) + '</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (l.memo ? ' data-memo="' + esc(l.memo) + '"' : '') + '>' + (l.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="location_modify.html?id=' + encodeURIComponent(l.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('locationCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: 'ロケーション',
    load: function () { return LocationStore.load(); },
    columns: [
      { key: 'code', label: 'ロケーションコード', type: 'text', required: false },
      { key: 'name', label: 'ロケーション名', type: 'text', required: true },
      { key: 'type', label: 'ロケーション区分コード', type: 'select', required: true, options: LocationTypeStore.load().map(function (x) { return x.code; }) },
      { key: 'tel', label: '電話番号', type: 'text', required: false },
      { key: 'address', label: '住所', type: 'text', required: false },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態コード', type: 'select', required: true, options: OperatingStatusStore.codes(),
        format: function (r) { return StoreImport.codeByName(OperatingStatusStore, r.status); },
        parse: function (v) { return OperatingStatusStore.nameOf(v); } }
    ],
    existingKeys: function () { return LocationStore.load().map(function (l) { return l.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = LocationStore.load();
      list.push({ code: o.code || LocationStore.nextCode(list), name: o.name, type: o.type, tel: o.tel, address: o.address, memo: o.memo, status: o.status });
      LocationStore.save(list);
    },
    update: function (o) {
      var list = LocationStore.load();
      list.forEach(function (l) {
        if (l.code === o.code) { l.name = o.name; l.type = o.type; l.tel = o.tel; l.address = o.address; l.memo = o.memo; l.status = o.status; }
      });
      LocationStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  StoreImport.bind(SHEET_SPEC, { export: 'locationExport', import: 'locationImport', file: 'locationImportFile', fileName: 'ロケーション.xlsx' });
})();

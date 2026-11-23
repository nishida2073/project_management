(function () {
  var body = document.getElementById('staffVenderBody');
  var list = StaffVenderStore.load();

  list.forEach(function (c) {
    var on = c.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.code) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + esc(c.tel) + '</td>' +
      '<td>' + esc(c.address) + '</td>' +
      '<td>' + esc(c.contactName) + '</td>' +
      '<td>' + dashOr(c.contactEmail) + '</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' data-memo="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="staff_vender_modify.html?id=' + encodeURIComponent(c.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('staffVenderCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: '実施担当ベンダー',
    load: function () { return StaffVenderStore.load(); },
    columns: [
      { key: 'code', label: '実施担当ベンダーコード', type: 'text', required: false },
      { key: 'name', label: '実施担当ベンダー名', type: 'text', required: true },
      { key: 'tel', label: '電話番号', type: 'text', required: false },
      { key: 'address', label: '住所', type: 'text', required: false },
      { key: 'contactName', label: '窓口担当者名', type: 'text', required: false },
      { key: 'contactEmail', label: 'メールアドレス', type: 'text', required: false },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態コード', type: 'select', required: true, options: OperatingStatusStore.codes(),
        format: function (r) { return StoreImport.codeByName(OperatingStatusStore, r.status); },
        parse: function (v) { return OperatingStatusStore.nameOf(v); } }
    ],
    existingKeys: function () { return StaffVenderStore.load().map(function (v) { return v.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = StaffVenderStore.load();
      list.push({ code: o.code || StaffVenderStore.nextCode(list), name: o.name, tel: o.tel, address: o.address, memo: o.memo, contactName: o.contactName, contactEmail: o.contactEmail, status: o.status });
      StaffVenderStore.save(list);
    },
    update: function (o) {
      var list = StaffVenderStore.load();
      list.forEach(function (v) {
        if (v.code === o.code) { v.name = o.name; v.tel = o.tel; v.address = o.address; v.memo = o.memo; v.contactName = o.contactName; v.contactEmail = o.contactEmail; v.status = o.status; }
      });
      StaffVenderStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  StoreImport.bind(SHEET_SPEC, { export: 'staffVenderExport', import: 'staffVenderImport', file: 'staffVenderImportFile', fileName: '実施担当ベンダー.xlsx' });
})();

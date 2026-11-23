(function () {

  var body = document.getElementById('customerBody');
  var list = CustomerStore.load();

  list.forEach(function (c) {
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.id) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + dashOr(c.staff) + '</td>' +
      '<td>' + dashOr(c.email) + '</td>' +
      '<td><span class="status-label ' + (c.status === OperatingStatusStore.nameOf('STOPPED') ? 'gray' : 'green') + '">' + (c.status === OperatingStatusStore.nameOf('STOPPED') ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' data-memo="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="customer_modify.html?id=' + encodeURIComponent(c.id) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('customerCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: '顧客',
    load: function () { return CustomerStore.load(); },
    columns: [
      { key: 'id', label: '顧客コード', type: 'text', required: false },
      { key: 'name', label: '顧客名', type: 'text', required: true },
      { key: 'staff', label: '担当者コード', type: 'select', required: false, options: StaffStore.load().map(function (x) { return x.code; }),
        format: function (r) { return StoreImport.codeByName(StaffStore, r.staff); },
        parse: function (v) { return StaffStore.nameOf(v); } },
      { key: 'email', label: 'メールアドレス', type: 'text', required: false },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態コード', type: 'select', required: true, options: OperatingStatusStore.codes(),
        format: function (r) { return StoreImport.codeByName(OperatingStatusStore, r.status); },
        parse: function (v) { return OperatingStatusStore.nameOf(v); } }
    ],
    existingKeys: function () { return CustomerStore.load().map(function (c) { return c.id; }); },
    keyOf: function (o) { return o.id; },
    add: function (o) {
      var list = CustomerStore.load();
      list.push({ id: o.id || CustomerStore.nextId(list), name: o.name, staff: o.staff, email: o.email, memo: o.memo, status: o.status });
      CustomerStore.save(list);
    },
    update: function (o) {
      var list = CustomerStore.load();
      list.forEach(function (c) {
        if (c.id === o.id) { c.name = o.name; c.staff = o.staff; c.email = o.email; c.memo = o.memo; c.status = o.status; }
      });
      CustomerStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  StoreImport.bind(SHEET_SPEC, { export: 'customerExport', import: 'customerImport', file: 'customerImportFile', fileName: '顧客.xlsx' });
})();

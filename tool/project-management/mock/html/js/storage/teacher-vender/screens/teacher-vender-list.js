(function () {
  var body = document.getElementById('vendorBody');
  var list = TeacherVenderStore.load();

  list.forEach(function (v) {
    var on = v.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(v.code) + '</td>' +
      '<td>' + esc(v.name) + '</td>' +
      '<td>' + esc(v.tel) + '</td>' +
      '<td>' + dashOr(v.address) + '</td>' +
      '<td>' + esc(v.contactName) + '</td>' +
      '<td>' + dashOr(v.contactEmail) + '</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (v.memo ? ' data-memo="' + esc(v.memo) + '"' : '') + '>' + (v.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="teacher_vender_modify.html?id=' + encodeURIComponent(v.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: '講師ベンダー',
    load: function () { return TeacherVenderStore.load(); },
    columns: [
      { key: 'code', label: 'コード', type: 'text', required: false },
      { key: 'name', label: '名称', type: 'text', required: true },
      { key: 'contract', label: '契約区分', type: 'select', required: false, options: ContractTypeStore.load().map(function (t) { return t.name; }),
        format: function (r) { return ContractTypeStore.nameOf(r.contract); },
        parse: function (t) { return StoreImport.codeByName(ContractTypeStore, t); } },
      { key: 'years', label: '稼働年度', type: 'text', required: false,
        format: function (r) { return (r.years || []).join(','); },
        parse: function (t) { return t.split(',').map(function (x) { return x.trim(); }).filter(Boolean); } },
      { key: 'tel', label: '電話番号', type: 'text', required: false },
      { key: 'address', label: '住所', type: 'text', required: false },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'contactName', label: '窓口担当者名', type: 'text', required: false },
      { key: 'contactEmail', label: 'メールアドレス', type: 'text', required: false },
      { key: 'status', label: '稼働状態', type: 'select', required: true, options: [OperatingStatusStore.nameOf('ACTIVE'), OperatingStatusStore.nameOf('STOPPED')] }
    ],
    existingKeys: function () { return TeacherVenderStore.load().map(function (v) { return v.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = TeacherVenderStore.load();
      list.push({ code: o.code || TeacherVenderStore.nextCode(list), name: o.name, contract: o.contract, years: o.years, tel: o.tel, address: o.address, memo: o.memo, contactName: o.contactName, contactEmail: o.contactEmail, status: o.status });
      TeacherVenderStore.save(list);
    },
    update: function (o) {
      var list = TeacherVenderStore.load();
      list.forEach(function (v) {
        if (v.code === o.code) { v.name = o.name; v.contract = o.contract; v.years = o.years; v.tel = o.tel; v.address = o.address; v.memo = o.memo; v.contactName = o.contactName; v.contactEmail = o.contactEmail; v.status = o.status; }
      });
      TeacherVenderStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  StoreImport.bind(SHEET_SPEC, { export: 'teacherVenderExport', import: 'teacherVenderImport', file: 'teacherVenderImportFile', fileName: '講師ベンダー.xlsx' });
})();

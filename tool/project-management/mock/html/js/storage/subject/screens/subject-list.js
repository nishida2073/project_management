(function () {

  var body = document.getElementById('subjectBody');
  var list = SubjectStore.load();

  list.forEach(function (s) {
    var on = s.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(s.code) + '</td>' +
      '<td><span class="tag subject-type-tag ' + (SubjectTypeStore.colorOf(s.type) || '') + '">' + esc(SubjectTypeStore.nameOf(s.type)) + '</span></td>' +
      '<td>' + esc(s.name) + '</td>' +
      '<td>' + ((s.versions || []).length ? s.versions.map(function (v) { return '<span class="chip tag-like blue">' + esc(v) + '</span>'; }).join(' ') : '-') + '</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (s.memo ? ' data-memo="' + esc(s.memo) + '"' : '') + '>' + (s.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="subject_modify.html?id=' + encodeURIComponent(s.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('subjectCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: '科目',
    load: function () { return SubjectStore.load(); },
    columns: [
      { key: 'code', label: '科目コード', type: 'text', required: true },
      { key: 'name', label: '科目名', type: 'text', required: true },
      { key: 'type', label: '科目区分コード', type: 'select', required: true, options: SubjectTypeStore.load().map(function (x) { return x.code; }) },
      { key: 'versions', label: '版', type: 'text', required: true,
        format: function (r) { return (r.versions || []).join(','); },
        parse: function (t) { return t.split(',').map(function (x) { return x.trim(); }).filter(Boolean); } },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態コード', type: 'select', required: true, options: OperatingStatusStore.codes(),
        format: function (r) { return StoreImport.codeByName(OperatingStatusStore, r.status); },
        parse: function (v) { return OperatingStatusStore.nameOf(v); } }
    ],
    existingKeys: function () {
      return SubjectStore.load().map(function (s) { return s.code; });
    },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = SubjectStore.load();
      list.push({ code: o.code, name: o.name, type: o.type, versions: o.versions, status: o.status, memo: o.memo });
      SubjectStore.save(list);
    },
    update: function (o) {
      var list = SubjectStore.load();
      list.forEach(function (s) {
        if (s.code === o.code) { s.name = o.name; s.type = o.type; s.versions = o.versions; s.status = o.status; s.memo = o.memo; }
      });
      SubjectStore.save(list);
    },
    refresh: function () { location.reload(); }
  };

  StoreImport.bind(SHEET_SPEC, { export: 'subjectExport', import: 'subjectImport', file: 'subjectImportFile', fileName: '科目.xlsx' });
})();

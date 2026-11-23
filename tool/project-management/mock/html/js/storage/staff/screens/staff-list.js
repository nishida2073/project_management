(function () {
  var ROLE_CLASS = {};
  StaffRoleStore.load().forEach(function (t) { ROLE_CLASS[t.code] = t.color; });
  var JOB_CLASS = {};
  JobTypeStore.load().forEach(function (t) { JOB_CLASS[t.code] = t.color; });
  var POS_CLASS = {};
  PositionStore.load().forEach(function (t) { POS_CLASS[t.code] = t.color; });

  var body = document.getElementById('staffBody');
  var list = StaffStore.load();

  list.forEach(function (t) {
    var on = t.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(t.code) + '</td>' +
      '<td><span class="tag affiliation-tag ' + (t.affiliation === AffiliationStore.nameOf('PARTNER') ? 'orange' : 'blue') + '">' + esc(t.affiliation) + '</span></td>' +
      '<td>' + (t.company ? esc(StaffVenderStore.nameOf(t.company)) : '-') + '</td>' +
      '<td>' + esc(t.name) + '</td>' +
      '<td>' + esc(t.email) + '</td>' +
      '<td><div class="tag-stack-col">' + (t.roles || []).map(function (r) { return '<span class="tag role-tag ' + (ROLE_CLASS[r] || '') + '">' + esc(StaffRoleStore.nameOf(r)) + '</span>'; }).join('') + '</div></td>' +
      '<td><div class="tag-stack-col">' + (t.jobTypes || []).map(function (j) { return '<span class="tag job-type-tag ' + (JOB_CLASS[j] || '') + '">' + esc(JobTypeStore.nameOf(j)) + '</span>'; }).join('') + '</div></td>' +
      '<td><div class="tag-stack">' + ((t.positions || []).length ? (t.positions || []).map(function (p) { return '<span class="tag position-tag ' + (POS_CLASS[p] || '') + '">' + esc(PositionStore.nameOf(p)) + '</span>'; }).join('') : '-') + '</div></td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (t.memo ? ' data-memo="' + esc(t.memo) + '"' : '') + '>' + (t.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="staff_modify.html?id=' + encodeURIComponent(t.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('staffCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: '実施担当者',
    load: function () { return StaffStore.load(); },
    columns: [
      { key: 'code', label: '実施担当者コード', type: 'text', required: false },
      { key: 'affiliation', label: '所属区分コード', type: 'select', required: true, options: AffiliationStore.load().map(function (a) { return a.code; }),
        format: function (r) { return StoreImport.codeByName(AffiliationStore, r.affiliation); },
        parse: function (v) { return AffiliationStore.nameOf(v); } },
      { key: 'company', label: '実施担当ベンダーコード', type: 'select', required: false, options: StaffVenderStore.load().map(function (x) { return x.code; }) },
      { key: 'name', label: '実施担当者名', type: 'text', required: true },
      { key: 'email', label: 'メールアドレス', type: 'text', required: false },
      { key: 'roles', label: '担当区分コード', type: 'list', required: false, options: StaffRoleStore.load().map(function (x) { return x.code; }) },
      { key: 'jobTypes', label: '業務区分コード', type: 'list', required: false, options: JobTypeStore.load().map(function (x) { return x.code; }) },
      { key: 'positions', label: '役職コード', type: 'list', required: false, options: PositionStore.load().map(function (x) { return x.code; }) },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態コード', type: 'select', required: true, options: OperatingStatusStore.codes(),
        format: function (r) { return StoreImport.codeByName(OperatingStatusStore, r.status); },
        parse: function (v) { return OperatingStatusStore.nameOf(v); } }
    ],
    existingKeys: function () { return StaffStore.load().map(function (s) { return s.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = StaffStore.load();
      list.push(staffRecord(o, StaffStore.nextCode(list)));
      StaffStore.save(list);
    },
    update: function (o) {
      var list = StaffStore.load();
      list.forEach(function (s) {
        if (s.code === o.code) {
          var rec = staffRecord(o, s.code);
          for (var k in rec) { s[k] = rec[k]; }
        }
      });
      StaffStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  function staffRecord(o, code) {
    return { code: code, affiliation: o.affiliation, company: o.company, name: o.name, email: o.email,
      roles: o.roles, jobTypes: o.jobTypes, positions: o.positions, memo: o.memo, status: o.status };
  }
  StoreImport.bind(SHEET_SPEC, { export: 'staffExport', import: 'staffImport', file: 'staffImportFile', fileName: '実施担当者.xlsx' });
})();

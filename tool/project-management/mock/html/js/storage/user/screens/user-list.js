(function () {

  var body = document.getElementById('userBody');
  var list = UserStore.load();

  function tagsOf(codes, store, cls) {
    return (codes || []).map(function (c) {
      return '<span class="tag ' + cls + ' ' + (store.colorOf(c) || '') + '">' + esc(store.nameOf(c)) + '</span>';
    }).join('') || '-';
  }

  list.forEach(function (u) {
    var on = u.status !== OperatingStatusStore.nameOf('STOPPED');
    var st = StaffStore.load().filter(function (s) { return s.email === u.email; })[0];
    var tr = document.createElement('tr');
    var roleNames = st ? (st.roles || []).map(function (c) { return StaffRoleStore.nameOf(c); }) : [];
    var jobNames = st ? (st.jobTypes || []).map(function (c) { return JobTypeStore.nameOf(c); }) : [];
    tr.setAttribute('data-affiliation', st ? st.affiliation : '');
    tr.setAttribute('data-roles', roleNames.join('|'));
    tr.setAttribute('data-jobs', jobNames.join('|'));
    tr.innerHTML =
      '<td>' + esc(u.code) + '</td>' +
      '<td>' + esc(u.name) + '</td>' +
      '<td>' + esc(u.email) + '</td>' +
      '<td><span class="tag user-role-tag ' + (UserRoleStore.colorOf(u.authority) || '') + '">' + esc(UserRoleStore.nameOf(u.authority)) + '</span></td>' +
      '<td><span class="tag link-state-tag ' + LinkStateStore.colorOf(st ? 'ON' : 'OFF') + '">' + esc(LinkStateStore.nameOf(st ? 'ON' : 'OFF')) + '</span></td>' +
      '<td>' + (st ? '<span class="tag affiliation-tag ' + (st.affiliation === AffiliationStore.nameOf('PARTNER') ? 'orange' : 'blue') + '">' + esc(st.affiliation) + '</span>' : '-') + '</td>' +
      '<td>' + (st && st.company ? esc(StaffVenderStore.nameOf(st.company)) : '-') + '</td>' +
      '<td>' + tagsOf(st ? st.roles : [], StaffRoleStore, 'role-tag') + '</td>' +
      '<td><div class="tag-stack-col">' + ((st ? st.jobTypes : []) || []).map(function (j) { return '<span class="tag job-type-tag ' + (JobTypeStore.colorOf(j) || '') + '">' + esc(JobTypeStore.nameOf(j)) + '</span>'; }).join('') + '</div></td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (u.memo ? ' data-memo="' + esc(u.memo) + '"' : '') + '>' + (u.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="user_modify.html?id=' + encodeURIComponent(u.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('userCount').textContent = list.length;
})();

(function () {
  var SHEET_SPEC = {
    sheetName: 'ユーザー',
    load: function () { return UserStore.load(); },
    columns: [
      { key: 'code', label: 'コード', type: 'text', required: false },
      { key: 'name', label: '名称', type: 'text', required: true },
      { key: 'email', label: 'メールアドレス', type: 'text', required: true },
      { key: 'authority', label: '権限', type: 'select', required: true, options: UserRoleStore.load().map(function (r) { return r.name; }),
        format: function (r) { return UserRoleStore.nameOf(r.authority); },
        parse: function (t) { return StoreImport.codeByName(UserRoleStore, t); } },
      { key: 'password', label: 'パスワード', type: 'text', required: false, format: function (r) { return r.password || ''; } },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態', type: 'select', required: true, options: [OperatingStatusStore.nameOf('ACTIVE'), OperatingStatusStore.nameOf('STOPPED')] }
    ],
    existingKeys: function () { return UserStore.load().map(function (u) { return u.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = UserStore.load();
      var rec = { code: o.code || UserStore.nextCode(list), name: o.name, email: o.email, authority: o.authority, memo: o.memo, status: o.status };
      if (o.password) rec.password = o.password;
      list.push(rec);
      UserStore.save(list);
    },
    update: function (o) {
      var list = UserStore.load();
      list.forEach(function (u) {
        if (u.code === o.code) {
          u.name = o.name; u.email = o.email; u.authority = o.authority; u.memo = o.memo; u.status = o.status;
          if (o.password) u.password = o.password;
        }
      });
      UserStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  StoreImport.bind(SHEET_SPEC, { export: 'userExport', import: 'userImport', file: 'userImportFile', fileName: 'ユーザー.xlsx' });
})();

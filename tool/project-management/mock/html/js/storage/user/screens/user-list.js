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

(function () {

  var body = document.getElementById('userBody');
  var list = UserStore.load();

  list.forEach(function (u) {
    var on = u.status !== OperatingStatusStore.nameOf('STOPPED');
    var st = StaffStore.load().filter(function (s) { return s.code === u.staffCode; })[0];
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(u.code) + '</td>' +
      '<td>' + esc(u.name) + '</td>' +
      '<td>' + esc(u.email) + '</td>' +
      '<td>' + esc(StaffStore.nameOf(u.staffCode || '')) + '</td>' +
      '<td>' + (st ? '<span class="tag affiliation-tag ' + (st.affiliation === AffiliationStore.nameOf('PARTNER') ? 'orange' : 'blue') + '">' + esc(st.affiliation) + '</span>' : '-') + '</td>' +
      '<td>' + (st && st.company ? esc(StaffVenderStore.nameOf(st.company)) : '-') + '</td>' +
      '<td><span class="tag ' + (UserRoleStore.colorOf(u.authority) || '') + '">' + esc(UserRoleStore.nameOf(u.authority)) + '</span></td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (u.memo ? ' data-memo="' + esc(u.memo) + '"' : '') + '>' + (u.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="user_modify.html?id=' + encodeURIComponent(u.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('userCount').textContent = list.length;
})();

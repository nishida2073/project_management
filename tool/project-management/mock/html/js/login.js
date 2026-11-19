(function () {
  ['userList', 'userRoleList', 'staffList'].forEach(function (key) {
    try { localStorage.removeItem(key); } catch (e) {}
  });
  function login() {
    var email = $('loginId').value.trim();
    var password = $('loginPassword').value;
    var user = UserStore.load().filter(function (u) { return u.email === email; })[0];
    if (!user || user.status === OperatingStatusStore.nameOf('STOPPED') || user.password !== password) {
      $('loginError').textContent = 'ログインIDまたはパスワードが正しくありません';
      return;
    }
    sessionStorage.setItem('loginUserCode', user.code);
    sessionStorage.setItem('loginIsAdmin', user.authority === 'AU-01' ? '1' : '0');
    sessionStorage.setItem('loginUserName', user.name);
    sessionStorage.setItem('loginRoleName', UserRoleStore.nameOf(user.authority));
    sessionStorage.setItem('loginRoleColor', UserRoleStore.colorOf(user.authority) || '');
    var staff = StaffStore.load().filter(function (s) { return s.email === user.email; })[0] || null;
    var company = staff ? (staff.affiliation === AffiliationStore.nameOf('INTERNAL') ? StaffVenderStore.INTERNAL : (staff.company || '')) : '';
    sessionStorage.setItem('loginCompany', company);
    sessionStorage.setItem('loginRoleNames', JSON.stringify(staff ? (staff.roles || []).map(function (c) { return StaffRoleStore.nameOf(c); }) : []));
    sessionStorage.setItem('loginJobNames', JSON.stringify(staff ? (staff.jobTypes || []).map(function (c) { return JobTypeStore.nameOf(c); }) : []));
    sessionStorage.setItem('loginRoleTags', JSON.stringify(staff ? (staff.roles || []).map(function (c) { return { name: StaffRoleStore.nameOf(c), color: StaffRoleStore.colorOf(c) || '' }; }) : []));
    sessionStorage.setItem('loginJobTags', JSON.stringify(staff ? (staff.jobTypes || []).map(function (c) { return { name: JobTypeStore.nameOf(c), color: JobTypeStore.colorOf(c) || '' }; }) : []));
    sessionStorage.setItem('loginAffiliationTag', JSON.stringify(staff ? { name: staff.affiliation, color: AffiliationStore.colorOf(AffiliationStore.codeOf(staff.affiliation)) || '' } : null));
    var target = sessionStorage.getItem('afterLogin');
    sessionStorage.removeItem('afterLogin');
    if (target && Access.canOpen(target)) {
      location.href = target;
    } else {
      location.href = Access.firstPage() || 'login.html';
    }
  }

  $('loginBtn').addEventListener('click', login);
  $('resetStorage').addEventListener('click', function () {
    if (!confirm('保存されたデータをすべて消去して、初期状態に戻します。よろしいですか？')) return;
    try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}
    location.reload();
  });
  ['loginId', 'loginPassword'].forEach(function (id) {
    $(id).addEventListener('keydown', function (e) {
      if (e.key === 'Enter') $('loginBtn').click();
    });
  });
})();

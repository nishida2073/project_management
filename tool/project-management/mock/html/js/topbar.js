(function () {
  var slot = document.getElementById('topbar-slot');
  if (!slot) return;
  slot.className = 'topbar';
  slot.innerHTML = '<div class="topbar-title-block"><div class="topbar-title"></div></div>' +
    '<div class="user" id="userMenu"><span class="tag user-role-tag" id="userRole"></span><span id="userName"></span><div class="avatar" id="userAvatar"></div>' +
    '<div class="user-menu" id="userMenuList"><div class="user-menu-info" id="userMenuTags"></div><div class="user-menu-pw"><div class="btn outline" id="pwBtn">パスワード変更</div></div><div class="user-menu-logout"><div class="btn primary" id="logoutBtn">ログアウト</div></div></div></div>';
  slot.querySelector('.topbar-title').textContent = slot.getAttribute('data-title') || '';
  var name = sessionStorage.getItem('loginUserName') || '未ログイン';
  document.getElementById('userName').textContent = name;
  var roleName = sessionStorage.getItem('loginRoleName') || '';
  var roleEl = document.getElementById('userRole');
  roleEl.textContent = roleName;
  if (sessionStorage.getItem('loginRoleColor')) roleEl.classList.add(sessionStorage.getItem('loginRoleColor'));
  if (!roleName) roleEl.style.display = 'none';
  var menuTags = document.getElementById('userMenuTags');
  if (sessionStorage.getItem('loginIsAdmin') !== '1') {
    var roleTags = JSON.parse(sessionStorage.getItem('loginRoleTags') || '[]').map(function (x) { return { cls: 'role-tag', name: x.name, color: x.color }; });
    var jobTags = JSON.parse(sessionStorage.getItem('loginJobTags') || '[]').map(function (x) { return { cls: 'job-type-tag', name: x.name, color: x.color }; });
    var affiliation = JSON.parse(sessionStorage.getItem('loginAffiliationTag') || 'null');
    var affTags = affiliation ? [{ cls: 'affiliation-tag', name: affiliation.name, color: affiliation.color }] : [];
    [['所属区分', affTags], ['担当区分', roleTags], ['業務区分', jobTags]].forEach(function (group) {
      if (!group[1].length) return;
      var row = document.createElement('div');
      row.className = 'user-menu-row';
      var label = document.createElement('span');
      label.className = 'user-menu-label';
      label.textContent = group[0];
      row.appendChild(label);
      group[1].forEach(function (x) {
        var tag = document.createElement('span');
        tag.className = 'tag ' + x.cls + ' ' + x.color;
        tag.textContent = x.name;
        row.appendChild(tag);
      });
      menuTags.appendChild(row);
    });
  }
  if (!menuTags.childNodes.length) menuTags.style.display = 'none';
  if (sessionStorage.getItem('loginRoleColor')) document.getElementById('userAvatar').classList.add('avatar-' + sessionStorage.getItem('loginRoleColor'));
  document.getElementById('userAvatar').textContent = name.split(' ')[0].charAt(0);
  document.getElementById('userAvatar').addEventListener('click', function () {
    document.getElementById('userMenuList').classList.toggle('open');
  });
  document.addEventListener('click', function (e) {
    if (!e.target.closest('#userMenu')) document.getElementById('userMenuList').classList.remove('open');
  });
  document.getElementById('logoutBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    try { sessionStorage.removeItem('loginUserCode'); sessionStorage.removeItem('loginIsAdmin'); sessionStorage.removeItem('loginRoleNames'); sessionStorage.removeItem('loginJobNames'); sessionStorage.removeItem('loginRoleTags'); sessionStorage.removeItem('loginJobTags'); sessionStorage.removeItem('loginAffiliationTag'); sessionStorage.removeItem('loginUserName'); sessionStorage.removeItem('loginRoleName'); sessionStorage.removeItem('loginRoleColor'); sessionStorage.removeItem('loginCompany'); } catch (err) {}
    location.href = 'login.html';
  });
  function loadScript(src, done) {
    var s = document.createElement('script');
    s.src = src;
    s.onload = done;
    document.head.appendChild(s);
  }

  function ensureUserStore(done) {
    if (window.UserStore) return done();
    var next = function () { loadScript('js/storage/user/store/user-store.js', done); };
    if (window.OperatingStatusStore) next();
    else loadScript('js/storage/operating-status/store/operating-status-store.js', next);
  }

  function ensureMessageDialog(done) {
    if (window.MessageDialog) return done();
    loadScript('js/message-dialog.js', done);
  }

  function openPasswordDialog() {
    var overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML = '<div class="input-dialog">' +
      '<div class="input-dialog-title">パスワード変更</div>' +
      '<div class="input-dialog-error" id="pwError"></div>' +
      '<label class="input-dialog-label">現在のパスワード</label><input type="password" class="form-control" id="pwCurrent">' +
      '<label class="input-dialog-label">新しいパスワード</label><input type="password" class="form-control" id="pwNew">' +
      '<label class="input-dialog-label">新しいパスワード（確認）</label><input type="password" class="form-control" id="pwConfirm">' +
      '<div class="input-dialog-actions"><div class="search-btn" id="pwCancel">キャンセル</div><div class="btn primary" id="pwOk">保存</div></div>' +
      '</div>';
    document.body.appendChild(overlay);
    function close() { overlay.remove(); }
    overlay.querySelector('#pwCancel').addEventListener('click', close);
    overlay.querySelector('#pwOk').addEventListener('click', function () {
      var error = overlay.querySelector('#pwError');
      var current = overlay.querySelector('#pwCurrent').value;
      var next = overlay.querySelector('#pwNew').value;
      var confirmValue = overlay.querySelector('#pwConfirm').value;
      var code = sessionStorage.getItem('loginUserCode');
      var list = UserStore.load();
      var idx = -1;
      list.forEach(function (u, i) { if (u.code === code) idx = i; });
      if (idx < 0 || list[idx].password !== current) { error.textContent = '現在のパスワードが正しくありません'; return; }
      if (!next) { error.textContent = '新しいパスワードを入力してください'; return; }
      if (next !== confirmValue) { error.textContent = '新しいパスワードが一致しません'; return; }
      list[idx] = Object.assign({}, list[idx], { password: next });
      UserStore.save(list);
      close();
      ensureMessageDialog(function () { MessageDialog.show('パスワードを変更しました'); });
    });
  }

  document.getElementById('pwBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    document.getElementById('userMenuList').classList.remove('open');
    ensureUserStore(openPasswordDialog);
  });
})();

(function () {
  var slot = document.getElementById('topbar-slot');
  if (!slot) return;
  slot.className = 'topbar';
  slot.innerHTML = '<div class="topbar-title-block"><div class="topbar-title"></div></div>' +
    '<div class="user" id="userMenu"><span class="tag user-role-tag" id="userRole"></span><span id="userName"></span><div class="avatar" id="userAvatar"></div>' +
    '<div class="user-menu" id="userMenuList"><div class="user-menu-info" id="userMenuTags"></div><div class="user-menu-logout"><div class="btn primary" id="logoutBtn">ログアウト</div></div></div></div>';
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
})();

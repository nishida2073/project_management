(function () {

  function fill(rec) {
    $('userCode').textContent = rec.code || '自動採番';
    $('userName').value = rec.name || '';
    $('userEmail').value = rec.email || '';
    $('userPassword').value = '';
    checkRadio('authority', rec.authority || 'AU-02');
    $('memo').value = rec.memo || '';
    var off = rec.status === OperatingStatusStore.labelOf('STOPPED');
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.labelOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.labelOf('STOPPED'));
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.labelOf('STOPPED') : OperatingStatusStore.labelOf('ACTIVE');
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = UserStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    renderRadios(document.getElementById('authorityGroup'), 'authority', UserRoleStore.load());

    if (editing) {
      list.forEach(function (u, i) { if (u.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象のユーザーが見つかりません', function () { location.href = 'user_list.html'; });
        return;
      }
      rec = list[idx];
      $('passwordField').style.display = '';
    } else {
      rec = { code: '', name: '', email: '', authority: 'AU-02', status: OperatingStatusStore.labelOf('ACTIVE') };
      $('passwordField').style.display = '';
    }

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = {
        name: $('userName').value.trim(),
        email: $('userEmail').value.trim(),
        authority: getRadio('authority'),
        memo: $('memo').value,
        status: readStatus()
      };
      var password = $('userPassword').value;
      var missing = [];
        if (!v.name) missing.push('ユーザー名');
        if (!v.email) missing.push('メールアドレス（ログインID）');
        if (!v.authority) missing.push('権限');
        if (!editing && !password) missing.push('初期パスワード');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (!editing && list.some(function (u) { return u.email === v.email; })) {
        MessageDialog.show('同じメールアドレスのユーザーが既に登録されています');
        return;
      }
      if (password) v.password = password;
      if (editing) {
        list[idx] = Object.assign({}, list[idx], v);
      } else {
        list.push(Object.assign({ code: UserStore.nextCode(list) }, v));
      }
      UserStore.save(list);
      location.href = 'user_list.html';
    });
  }

  window.UserEditor = { init: init };
})();

(function () {
  function renderChecks(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="multi-opt" data-tone="' + esc(it.color || '') + '"><input type="checkbox" name="' + name + '" value="' + esc(it.code) + '"><span>' + esc(it.name) + '</span></label>';
    }).join('');
  }
  function setChecks(name, values) {
    document.querySelectorAll('input[name="' + name + '"]').forEach(function (c) {
      c.checked = (values || []).indexOf(c.value) !== -1;
    });
  }
  function getChecks(name) {
    return Array.prototype.map.call(document.querySelectorAll('input[name="' + name + '"]:checked'), function (c) { return c.value; });
  }

  function refreshCompany() {
    var partner = getRadio('affiliation') === AffiliationStore.nameOf('PARTNER');
    $('companyField').style.visibility = partner ? 'visible' : 'hidden';
  }

  function fill(rec) {
    $('staffCode').textContent = rec.code || '自動採番';
    checkRadio('affiliation', rec.affiliation || '');
    var company = $('company');
    company.setAttribute('data-value', StaffVenderStore.nameOf(rec.company));
    company.innerHTML = (rec.company ? esc(StaffVenderStore.nameOf(rec.company)) : '選択してください') + '<span class="caret">▾</span>';
    $('tName').value = rec.name || '';
    $('email').value = rec.email || '';
    setChecks('roles', rec.roles);
    setChecks('jobTypes', rec.jobTypes);
    setChecks('positions', rec.positions);
    $('memo').value = rec.memo || '';
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    var off = rec.status === OperatingStatusStore.nameOf('STOPPED');
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    refreshCompany();
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = StaffStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    $('company').setAttribute('data-options', StaffVenderStore.activeNames().join(','));
    renderChecks($('roleGroup'), 'roles', StaffRoleStore.load());
    renderChecks($('jobGroup'), 'jobTypes', JobTypeStore.load());
    renderChecks($('positionGroup'), 'positions', PositionStore.load());

    if (editing) {
      list.forEach(function (t, i) { if (t.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象の実施担当者が見つかりません', function () { location.href = 'staff_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', affiliation: '', company: '', name: '', email: '', roles: [], jobTypes: [], positions: [], status: OperatingStatusStore.nameOf('ACTIVE') };
    }
    fill(rec);
    document.querySelectorAll('input[name="affiliation"]').forEach(function (r) { r.addEventListener('change', refreshCompany); });

    $('saveBtn').addEventListener('click', function () {
      var affiliation = getRadio('affiliation');
      var company = affiliation === AffiliationStore.nameOf('INTERNAL') ? '' : StaffVenderStore.codeOf(ownText($('company')));
      if (company === '選択してください') company = '';
      var v = {
        affiliation: affiliation,
        company: company,
        name: $('tName').value.trim(),
        email: $('email').value.trim(),
        roles: getChecks('roles'),
        jobTypes: getChecks('jobTypes'),
        positions: getChecks('positions'),
        memo: $('memo').value,
        status: readStatus()
      };
      var missing = [];
        if (!v.name) missing.push('実施担当者名');
        if (!v.affiliation) missing.push('所属区分');
        if (!v.roles.length) missing.push('担当区分');
        if (!v.jobTypes.length) missing.push('業務区分');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (v.affiliation === AffiliationStore.nameOf('PARTNER') && !v.company) {
        MessageDialog.required(['実施担当ベンダー']);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: StaffStore.nextCode(list) }, v));
      }
      StaffStore.save(list);
      location.href = 'staff_list.html';
    });
  }

  window.StaffEditor = { init: init };
})();

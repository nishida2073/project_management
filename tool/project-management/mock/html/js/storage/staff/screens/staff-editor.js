(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function makeChip(value, cls) {
    var chip = document.createElement('span');
    chip.className = 'chip ' + cls;
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    return chip;
  }
  function chipValues(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (c) {
      return c.textContent.replace('✕', '').trim();
    });
  }
  function fillChips(box, values, classOf) {
    var addBtn = box.querySelector('.chip-add');
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    values.forEach(function (v) { box.insertBefore(makeChip(v, classOf(v)), addBtn); });
  }

  function nameFromCode(list, code) {
    var f = list.filter(function (t) { return t.code === code; })[0];
    return f ? f.name : code;
  }
  function codeFromName(list, name) {
    var f = list.filter(function (t) { return t.name === name; })[0];
    return f ? f.code : name;
  }
  function colorFromName(list, name) {
    var f = list.filter(function (t) { return t.name === name; })[0];
    return f ? f.color : '';
  }

  function refreshCompany() {
    var partner = getRadio('affiliation') === 'パートナー';
    $('companyField').style.visibility = partner ? 'visible' : 'hidden';
  }

  function fill(rec) {
    $('staffCode').textContent = rec.code || '自動採番';
    checkRadio('affiliation', rec.affiliation || '社内');
    var company = $('company');
    company.setAttribute('data-value', StaffVenderStore.nameOf(rec.company));
    company.innerHTML = (rec.company ? esc(StaffVenderStore.nameOf(rec.company)) : '選択してください') + '<span class="caret">▾</span>';
    $('tName').value = rec.name || '';
    $('email').value = rec.email || '';
    var roleList = StaffRoleStore.load();
    var posList = PositionStore.load();
    fillChips($('roleBox'), (rec.roles || []).map(function (c) { return nameFromCode(roleList, c); }), function (v) { return colorFromName(roleList, v); });
    checkRadio('jobType', rec.jobType || 'JT-02');
    fillChips($('positionBox'), (rec.positions || []).map(function (c) { return nameFromCode(posList, c); }), function (v) { return colorFromName(posList, v); });
    var row = $('statusRow');
    row.setAttribute('data-on', '稼働中');
    row.setAttribute('data-off', '停止中');
    var off = rec.status === '停止中';
    $('statusToggle').classList.toggle('off', off);
    $('statusLabel').textContent = off ? '停止中' : '稼働中';
    refreshCompany();
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = StaffStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    $('company').setAttribute('data-options', StaffVenderStore.activeNames().join(','));

    if (editing) {
      list.forEach(function (t, i) { if (t.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象の実施担当者が見つかりません', function () { location.href = 'staff_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', affiliation: '社内', company: '', name: '', email: '', roles: [], jobType: 'JT-02', positions: [], status: '稼働中' };
    }
    renderRadios(document.getElementById('jobGroup'), 'jobType', JobTypeStore.load());
    fill(rec);
    var roles = StaffRoleStore.load();
    $('roleBox').setAttribute('data-options', roles.map(function (r) { return r.name; }).join(','));
    $('roleBox').setAttribute('data-chip-map', JSON.stringify(roles.reduce(function (m, r) { m[r.name] = r.color; return m; }, {})));
    var positions = PositionStore.load();
    $('positionBox').setAttribute('data-options', positions.map(function (p) { return p.name; }).join(','));
    $('positionBox').setAttribute('data-chip-map', JSON.stringify(positions.reduce(function (m, p) { m[p.name] = p.color; return m; }, {})));
    document.querySelectorAll('input[name="affiliation"]').forEach(function (r) { r.addEventListener('change', refreshCompany); });

    $('saveBtn').addEventListener('click', function () {
      var affiliation = getRadio('affiliation');
      var company = affiliation === '社内' ? '' : StaffVenderStore.codeOf(ownText($('company')));
      if (company === '選択してください') company = '';
      var v = {
        affiliation: affiliation,
        company: company,
        name: $('tName').value.trim(),
        email: $('email').value.trim(),
        roles: chipValues($('roleBox')).map(function (n) { return codeFromName(StaffRoleStore.load(), n); }),
        jobType: getRadio('jobType'),
        positions: chipValues($('positionBox')).map(function (n) { return codeFromName(PositionStore.load(), n); }),
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
      };
      var missing = [];
        if (!v.name) missing.push('実施担当者名');
        if (!v.affiliation) missing.push('所属区分');
        if (!v.roles.length) missing.push('担当区分');
        if (!v.jobType) missing.push('業務区分');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (v.affiliation === 'パートナー' && !v.company) {
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

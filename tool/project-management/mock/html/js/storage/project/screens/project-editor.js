(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function clean(s) { return s === '選択してください' ? '' : s; }
  function setSelect(el, value) {
    var v = value || '';
    el.setAttribute('data-value', v);
    el.innerHTML = (v ? esc(v) : '選択してください') + '<span class="caret">▾</span>';
  }
  function getSelect(el) { return clean(ownText(el)); }
  function setMonth(el, value) {
    el.innerHTML = (value ? esc(value) : '') + '<span class="caret">▾</span>';
  }
  function getMonth(el) { return ownText(el); }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function makeChip(value) {
    var chip = document.createElement('span');
    chip.className = 'chip orange';
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    return chip;
  }
  function plValues(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (c) {
      return c.textContent.replace('✕', '').trim();
    });
  }

  function renderGroup(name, items) {
    var group = document.querySelector('input[name="' + name + '"]').closest('.radio-group');
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function fill(rec) {
    setSelect($('projectYear'), rec.year);
    $('projectCode').textContent = rec.code || '自動採番';
    checkRadio('salesType', rec.sales || '');
    checkRadio('participationType', rec.part || '');
    var statusOff = rec.status === '停止中';
    $('statusRow').setAttribute('data-on', '稼働中');
    $('statusRow').setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', statusOff);
    $('statusLabel').textContent = statusOff ? '停止中' : '稼働中';
    $('projectName').value = rec.name || '';
    setSelect($('customer'), CustomerStore.nameOf(rec.customer));
    setMonth($('startMonth'), rec.startMonth);
    setSelect($('pm'), StaffStore.nameOf(rec.pm));
    var box = $('plBox');
    var addBtn = box.querySelector('.chip-add');
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (rec.pl || []).forEach(function (p) { box.insertBefore(makeChip(StaffStore.nameOf(p)), addBtn); });
    $('memo').value = rec.memo || '';
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    renderGroup('salesType', SalesTypeStore.load());
    renderGroup('participationType', ParticipationTypeStore.load());
    var projectStaff = StaffStore.candidates({ affiliations: ['社内'], roles: ['案件'], jobTypes: ['販売'] }).join(',');
    document.getElementById('pm').setAttribute('data-options', projectStaff);
    document.getElementById('plBox').setAttribute('data-options', projectStaff);
    document.getElementById('customer').setAttribute('data-options', CustomerStore.load().filter(function (c) { return c.status !== '停止中'; }).map(function (c) { return c.name; }).join(','));
    var list = ProjectStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (p, i) { if (p.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象の案件が見つかりません', function () { location.href = 'project_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { year: '2026', code: '', sales: '', part: '', name: '', customer: '', startMonth: '', pm: '', pl: [], memo: '', status: '稼働中' };
    }
    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = {
        year: getSelect($('projectYear')),
        sales: getRadio('salesType'),
        part: getRadio('participationType'),
        name: $('projectName').value.trim(),
        customer: CustomerStore.codeOf(getSelect($('customer'))),
        startMonth: getMonth($('startMonth')),
        pm: StaffStore.codeOf(getSelect($('pm'))),
        pl: plValues($('plBox')).map(function (n) { return StaffStore.codeOf(n); }),
        memo: $('memo').value,
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
      };
      var missing = [];
        if (!v.year) missing.push('年度');
        if (!v.sales) missing.push('販売区分');
        if (!v.part) missing.push('参加区分');
        if (!v.name) missing.push('案件名');
        if (!v.startMonth) missing.push('実施開始月');
        if (!v.pm) missing.push('PM');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: ProjectStore.nextCode(list) }, v));
      }
      ProjectStore.save(list);
      location.href = 'project_list.html';
    });
  }

  window.ProjectEditor = { init: init };
})();

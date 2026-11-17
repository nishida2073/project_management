(function () {


  function chooseWithdraw(names) {
    return SelectDialog.open({
      title: '依頼の取り下げ',
      fields: [{ label: '講師ベンダー名', select: { options: names, value: names.length === 1 ? names[0] : '' } }],
      okLabel: '取り下げる'
    });
  }

  function vendorOptions() { return TeacherVenderStore.activeNames(); }

  function makeRow(listId, data) {
    var row = document.createElement('div');
    row.className = 'sub-grid sub-row';
    row.setAttribute('data-state', data.locked ? 'requesting' : (data.state || ''));
    var reference = data.state === 'done' || data.state === 'requesting' || !!data.locked;
    var vendorName = TeacherVenderStore.nameOf(data.vendor) || '-';
    var vendorCell;
    if (data.locked || data.state === 'requesting') {
      vendorCell = '<div class="form-control readonly vendor-fixed" data-code="' + esc(data.vendor) + '">' + esc(vendorName) + '</div>';
    } else if (reference) {
      vendorCell = '<div class="form-control readonly vendor-before" data-code="' + esc(data.vendor) + '">' + esc(vendorName) + '</div>';
    } else {
      vendorCell = '<div class="form-control js-select" data-options="' + esc(vendorOptions().join(',')) + '">' + esc(TeacherVenderStore.nameOf(data.vendor) || '選択してください') + '<span class="caret">▾</span></div>';
    }
    row.innerHTML =
      vendorCell +
      '<input type="text" class="form-control' + (reference ? ' readonly' : '') + '" placeholder="講師名"' + (reference ? ' disabled' : '') + ' value="' + esc(data.teacherName || '') + '">' +
      '<div class="sub-remove">✕</div>' +
      '<span class="tag fixed sub-status"></span>';
    row.querySelector('.sub-remove').addEventListener('click', function () {
      var st = row.getAttribute('data-state');
      if (st !== 'done' && st !== 'requesting') { row.remove(); return; }
      var head = st === 'done' ? SlotStatusStore.labelOf('REQUESTED') + 'の担当者を削除します' : SlotStatusStore.labelOf('REQUESTING') + 'を削除します';
      MessageDialog.confirm([head, '', '削除してよろしいですか？'].join(String.fromCharCode(10))).then(function (ok) {
        if (ok) row.remove();
      });
    });
    $(listId).appendChild(row);
    Array.prototype.forEach.call(row.querySelectorAll('.js-select'), function (el) { window.bindJsSelect(el); });
  }

  var S = VenderAssignStore.STATUS;

  function statusOfRow(row) {
    if (isDoneRow(row)) return S.REQUESTED;
    if (row.querySelector('.vendor-fixed')) return S.REQUESTING;
    if (row.querySelector('.vendor-before')) return S.BEFORE;
    var sel = row.querySelector('.js-select');
    if (sel && placeholderToEmpty(ownText(sel))) return S.BEFORE;
    return S.OPEN;
  }

  function isDoneRow(row) {
    return row.getAttribute('data-state') === 'done';
  }
  function refreshStatuses() {
    Array.prototype.forEach.call(document.querySelectorAll('#mainList .sub-row, #subList .sub-row'), function (row) {
      var st = statusOfRow(row);
      var tag = row.querySelector('.sub-status');
      tag.className = 'tag fixed sub-status' + (st ? ' ' + st.tag : '');
      tag.textContent = st ? st.label : '';
    });
  }

  function readRows(listId) {
    var out = [];
    Array.prototype.forEach.call($(listId).querySelectorAll('.sub-row'), function (row) {
      var sel = row.querySelectorAll('.js-select');
      var fixed = !!row.querySelector('.vendor-fixed');
      var refEl = row.querySelector('[data-code]');
      var vendor = refEl ? refEl.getAttribute('data-code') : TeacherVenderStore.codeOf(placeholderToEmpty(ownText(sel[0])));
      var name = (row.querySelector('input[type="text"]') || { value: '' }).value.trim();
      if (isDoneRow(row)) { out.push({ vendor: vendor, teacherName: name, state: 'done' }); return; }
      if (fixed) { if (name) out.push({ vendor: vendor, teacherName: name, state: 'requesting' }); return; }
      if (!vendor) return;
      out.push({ vendor: vendor, teacherName: name, state: 'before' });
    });
    return out;
  }

  function init(opts) {
    var classId = new URLSearchParams(location.search).get('id');
    var cls = null;
    ClassStore.load().forEach(function (r) { if (r.id === classId) cls = r; });
    if (!cls) {
      MessageDialog.show('対象の登壇依頼が見つかりません', function () { location.href = 'vender_assign_list.html'; });
      return;
    }
    var c = ClassStore.COURSES[cls.courseCode];
    $('subLine').textContent = cls.lessonNo + '　' + (c ? c.name : cls.courseCode) + '　予定講師数：メイン' + (cls.mainTeachers || '-') + '人・サブ' + (cls.subTeachers || '-') + '人';

    var a = VenderAssignStore.find(classId);
    var zanNow = a.mains.length < (parseInt(cls.mainTeachers, 10) || 0) || a.subs.length < (parseInt(cls.subTeachers, 10) || 0);
    var zanTag = document.createElement('span');
    zanTag.className = 'tag fixed ' + (zanNow ? 'orange' : 'green');
    zanTag.textContent = zanNow ? 'あり' : 'なし';
    $('subLine').appendChild(document.createTextNode('　残講師：'));
    $('subLine').appendChild(zanTag);
    var planMain = parseInt(cls.mainTeachers, 10) || 0;
    var planSub = parseInt(cls.subTeachers, 10) || 0;
    var mainRows = a.mains.slice();
    var reqs = VenderAssignStore.requestsOf(a);
    var reqNames = {};
    reqs.forEach(function (rq) { reqNames[TeacherVenderStore.nameOf(rq.vendor) || rq.vendor] = rq.vendor; });
    var requesting = a.mains.concat(a.subs).filter(function (m) { return m.state === 'requesting' && m.vendor; });
    requesting.forEach(function (m) { reqNames[TeacherVenderStore.nameOf(m.vendor) || m.vendor] = m.vendor; });
    if (reqs.length || requesting.length) $('withdrawBtn').style.display = '';
    $('withdrawBtn').addEventListener('click', function () {
      chooseWithdraw(Object.keys(reqNames)).then(function (name) {
        if (!name) return;
        var code = reqNames[name];
        var rec = VenderAssignStore.find(classId);
        rec.requests = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor !== code; });
        rec.mains = (rec.mains || []).filter(function (m) { return !(m.state === 'requesting' && m.vendor === code); });
        rec.subs = (rec.subs || []).filter(function (m) { return !(m.state === 'requesting' && m.vendor === code); });
        delete rec.requested;
        delete rec.requestMain;
        delete rec.requestSub;
        delete rec.requestVendor;
        VenderAssignStore.upsert(rec);
        location.href = 'vender_assign_list.html';
      });
    });
    reqs.forEach(function (rq) {
      for (var mq = 0; mq < (rq.main || 0); mq++) mainRows.push({ vendor: rq.vendor, teacherName: '', locked: !!rq.vendor });
    });
    while (mainRows.length < planMain) mainRows.push({ vendor: '', teacherName: '' });
    var subRows = a.subs.slice();
    reqs.forEach(function (rq) {
      for (var sq = 0; sq < (rq.sub || 0); sq++) subRows.push({ vendor: rq.vendor, teacherName: '', locked: !!rq.vendor });
    });
    while (subRows.length < planSub) subRows.push({ vendor: '', teacherName: '' });
    mainRows.forEach(function (m) { makeRow('mainList', m); });
    subRows.forEach(function (s) { makeRow('subList', s); });
    $('attendeeVendor').value = a.attendeeVendor || '';
    $('attendee').value = a.attendee || '';
    $('motivationVendor').innerHTML = MotivationCompanyTypeStore.load().map(function (t) {
      return '<label class="radio-option"><input type="radio" name="motivationVendor" value="' + esc(t.code) + '"><span class="radio-dot"></span><span class="tag ' + esc(t.color) + '">' + esc(t.name) + '</span></label>';
    }).join('');
    Array.prototype.forEach.call(document.querySelectorAll('input[name="motivationVendor"]'), function (r) { r.checked = r.value === (a.motivationVendor || ''); });
    $('motivationName').value = a.motivationName || '';
    $('memo').value = a.memo || '';

    function addRow(listId) {
      makeRow(listId, { vendor: '', teacherName: '' });
    }
    $('addMain').addEventListener('click', function () { addRow('mainList'); });
    $('addSub').addEventListener('click', function () { addRow('subList'); });
    refreshStatuses();
    document.addEventListener('input', refreshStatuses);
    document.addEventListener('click', function () { setTimeout(refreshStatuses, 0); }, true);

    $('saveBtn').addEventListener('click', function () {
      var mains = readRows('mainList');
      var subs = readRows('subList');
      if (reqs.length) {
        var noVendor = Array.prototype.some.call(document.querySelectorAll('#mainList .sub-row, #subList .sub-row'), function (row) {
          var teacherInput = row.querySelector('input[type="text"]');
          if (!teacherInput || !teacherInput.value.trim()) return false;
          var sel = row.querySelector('.js-select');
          return !!sel && sel.textContent.replace('▾', '').trim() === '選択してください';
        });
        if (noVendor) {
          MessageDialog.required([SlotStatusStore.labelOf('REQUESTING') + 'の会社名']);
          return;
        }
      }
      var record = {
        classId: classId,
        mainCount: a.mainCount,
        subCount: a.subCount,
        mains: mains,
        subs: subs,
        attendeeVendor: $('attendeeVendor').value.trim(),
        attendee: $('attendee').value.trim(),
        motivationVendor: (document.querySelector('input[name="motivationVendor"]:checked') || { value: '' }).value,
        motivationName: $('motivationName').value.trim(),
        memo: $('memo').value
      };
      var countPresent = function (listId) {
        var m = {};
        document.querySelectorAll('#' + listId + ' .sub-row').forEach(function (row) {
          var fx = row.querySelector('.vendor-fixed');
          if (!fx) return;
          if (row.getAttribute('data-state') !== 'requesting') return;
          if ((row.querySelector('input[type="text"]') || { value: '' }).value.trim()) return;
          var code = fx.getAttribute('data-code');
          m[code] = (m[code] || 0) + 1;
        });
        return m;
      };
      var presentM = countPresent('mainList');
      var presentS = countPresent('subList');
      var adjReqs = VenderAssignStore.requestsOf(a).map(function (r) {
        return { vendor: r.vendor, main: Math.min(r.main || 0, presentM[r.vendor] || 0), sub: Math.min(r.sub || 0, presentS[r.vendor] || 0) };
      }).filter(function (r) { return r.main > 0 || r.sub > 0; });
      record.requests = adjReqs;
      var reqMainTotal = adjReqs.reduce(function (t, r) { return t + r.main; }, 0);
      var reqSubTotal = adjReqs.reduce(function (t, r) { return t + r.sub; }, 0);
      var newMain = document.querySelectorAll('#mainList .sub-row').length;
      var newSub = document.querySelectorAll('#subList .sub-row').length;
      var over = newMain > planMain || newSub > planSub;
      function finish() {
        VenderAssignStore.upsert(Object.assign({}, a, record));
        location.href = 'vender_assign_list.html';
      }
      var planMainNext = Math.max(document.querySelectorAll('#mainList .sub-row').length, newMain);
      var planSubNext = Math.max(document.querySelectorAll('#subList .sub-row').length, newSub);
      var reduceLines = [];
      if (planMainNext < planMain) reduceLines.push('予定講師数（メイン）：' + planMain + ' → ' + planMainNext);
      if (planSubNext < planSub) reduceLines.push('予定講師数（サブ）：' + planSub + ' → ' + planSubNext);
      function setClassPlan(m, sb) {
        var list = ClassStore.load();
        list.forEach(function (r) {
          if (r.id === classId) {
            r.mainTeachers = String(m);
            r.subTeachers = String(sb);
          }
        });
        ClassStore.save(list);
      }
      if (!over && reduceLines.length) {
        MessageDialog.confirm(['枠が予定より少なくなっています', '予定講師数を減らしますか？', ''].concat(reduceLines).join(String.fromCharCode(10))).then(function (ok) {
          if (!ok) return;
          setClassPlan(planMainNext, planSubNext);
          finish();
        });
        return;
      }
      if (!over) { finish(); return; }
      var lines = ['予定講師数を超えています', '', '以下に変更してよろしいですか？'];
      if (newMain !== planMain) lines.push('予定講師数（メイン）：' + planMain + ' → ' + newMain);
      if (newSub !== planSub) lines.push('予定講師数（サブ）：' + planSub + ' → ' + newSub);
      MessageDialog.confirm(lines.join('\n')).then(function (ok) {
        if (!ok) return;
        var list = ClassStore.load();
        list.forEach(function (r) {
          if (r.id === classId) {
            r.mainTeachers = String(newMain);
            r.subTeachers = String(newSub);
          }
        });
        ClassStore.save(list);
        finish();
      });
    });
  }

  window.VenderAssignEditor = { init: init };
})();

(function () {

  var raw = sessionStorage.getItem('venderImportPlan');
  var plan = raw ? JSON.parse(raw) : null;
  if (!plan || !plan.updates || !plan.updates.length) {
    var card = document.querySelector('.table-card');
    if (card) card.style.display = 'none';
    return;
  }

  $('vendorLine').textContent = plan.vendorName || plan.vendorCode;

  function vendorText(v) {
    return TeacherVenderStore.nameOf(v) || v;
  }

  function sameTeacher(p, q) {
    return vendorText(q.vendor) === vendorText(p.vendor) && String(q.teacherName || '').trim() === String(p.teacherName || '').trim();
  }

  function stateOf(u, role) {
    var rec = VenderAssignStore.find(u.classId) || {};
    var reqs = VenderAssignStore.requestsOf(rec).filter(function (r) {
      return (role === 'sub' ? r.sub : r.main) > 0;
    });
    if (!reqs.length) return 'none';
    if (reqs.some(function (r) { return r.vendor === plan.vendorCode; })) return 'same';
    return 'diff';
  }

  function existingOf(u) {
    var a = VenderAssignStore.find(u.classId) || {};
    return { mains: a.mains || [], subs: a.subs || [] };
  }

  function cellHtml(u, idx, role, existing, add) {
    var state = stateOf(u, role);
    var rows = existing.map(function (m) {
      return esc(vendorText(m.vendor)) + '：' + esc(m.teacherName);
    });
    add.forEach(function (p, i) {
      var dup = existing.some(function (q) { return sameTeacher(p, q); });
      if (dup) return;
      var on = state === 'same';
      var tag = on
        ? ' <span class="tag green" style="font-size:10px;">追加</span>'
        : ' ' + VenderAssignStore.tag(VenderAssignStore.STATUS.NONE, 'font-size:10px;');
      rows.push('<label class="check-box check-sm" style="vertical-align:middle;"><input type="checkbox" class="import-check" data-idx="' + idx + '" data-role="' + role + '" data-i="' + i + '"' + (on ? ' checked' : '') + '><span class="check-mark"></span></label> ' +
        esc(vendorText(p.vendor)) + '：' + esc(p.teacherName) + tag);
    });
    return rows.length ? rows.join('<br>') : '-';
  }

  var newTotal = 0;
  plan.updates.forEach(function (u) {
    var ex = existingOf(u);
    (u.mains || []).forEach(function (p) { if (!ex.mains.some(function (q) { return sameTeacher(p, q); })) newTotal++; });
    (u.subs || []).forEach(function (p) { if (!ex.subs.some(function (q) { return sameTeacher(p, q); })) newTotal++; });
  });
  if (!newTotal) {
    sessionStorage.removeItem('venderImportPlan');
    MessageDialog.show('反映する内容がありません（すべて反映済みです）');
    return;
  }
  plan.updates.forEach(function (u, idx) {
    var ex = existingOf(u);
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(yearLabel(u.year)) + '</td>' +
      '<td><div>' + esc(u.courseName) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(u.courseCode) + '</div></td>' +
      '<td>' + esc(u.lessonNo) + '</td>' +
      '<td>' + esc(u.start) + '</td>' +
      '<td>' + esc(u.end) + '</td>' +
      '<td>' + cellHtml(u, idx, 'main', ex.mains, u.mains) + '</td>' +
      '<td>' + cellHtml(u, idx, 'sub', ex.subs, u.subs) + '</td>';
    $('importBody').appendChild(tr);
  });

  updateCount();

  if (plan.errors && plan.errors.length) {
    var msg = '反映できない内容（' + plan.errors.length + '件）:\n' + plan.errors.slice(0, 10).join('\n');
    if (plan.errors.length > 10) msg += '\nほか' + (plan.errors.length - 10) + '件';
    $('errorBox').textContent = msg;
  }

  function checkedBoxes() {
    return Array.prototype.slice.call($('importBody').querySelectorAll('.import-check:checked'));
  }

  function updateCount() {
    $('importTotal').textContent = checkedBoxes().length;
  }

  $('importBody').addEventListener('change', function (e) {
    if (e.target.classList.contains('import-check')) updateCount();
  });
  updateCount();

  function mergeUnique(list, add) {
    add.forEach(function (p) {
      var dup = list.some(function (q) { return sameTeacher(p, q); });
      if (!dup) list.push(p);
    });
    return list;
  }

  $('importApply').addEventListener('click', function () {
    if (!checkedBoxes().length) {
      MessageDialog.show('反映する項目を選択してください');
      return;
    }
    var picked = {};
    checkedBoxes().forEach(function (cb) {
      var idx = Number(cb.getAttribute('data-idx'));
      var role = cb.getAttribute('data-role');
      var i = Number(cb.getAttribute('data-i'));
      var u = plan.updates[idx];
      picked[idx] = picked[idx] || { mains: [], subs: [] };
      var src = role === 'sub' ? u.subs : u.mains;
      picked[idx][role === 'sub' ? 'subs' : 'mains'].push(src[i]);
    });
    var people = 0;
    try {
      Object.keys(picked).forEach(function (key) {
        var u = plan.updates[Number(key)];
        var a = VenderAssignStore.find(u.classId);
        var beforeM = a.mains.length;
        var beforeS = a.subs.length;
        a.mains = mergeUnique(a.mains, picked[key].mains);
        a.subs = mergeUnique(a.subs, picked[key].subs);
        var addM = a.mains.length - beforeM;
        var addS = a.subs.length - beforeS;
        var reqs = VenderAssignStore.requestsOf(a).map(function (r) {
          return { vendor: r.vendor, main: r.main || 0, sub: r.sub || 0 };
        });
        reqs.forEach(function (r) {
          if (r.vendor !== plan.vendorCode) return;
          var t = Math.min(r.main, addM);
          r.main -= t;
          addM -= t;
          t = Math.min(r.sub, addS);
          r.sub -= t;
          addS -= t;
        });
        a.requests = reqs.filter(function (r) { return r.main > 0 || r.sub > 0; });
        delete a.requested;
        delete a.requestMain;
        delete a.requestSub;
        delete a.requestVendor;
        VenderAssignStore.upsert(a);
        people += picked[key].mains.length + picked[key].subs.length;
      });
    } catch (e) {
      MessageDialog.show('反映に失敗しました（' + e.message + '）');
      return;
    }
    sessionStorage.removeItem('venderImportPlan');
    var msg = '反映が完了しました\n反映: ' + people + '人（' + Object.keys(picked).length + 'クラス）';
    MessageDialog.show(msg, function () { location.href = 'vender_assign_list.html'; });
  });
})();

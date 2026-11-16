(function () {

  var raw = sessionStorage.getItem('venderImportPlan');
  var plan = raw ? JSON.parse(raw) : null;
  var noPlan = !plan || !plan.updates || !plan.updates.length;
  if (noPlan) {
    plan = { updates: [], errors: [], vendorName: '', vendorCode: '' };
    var card = document.querySelector('.modal-body .table-card');
    if (card) card.style.display = 'none';
  }

  $('vendorLine').textContent = plan.vendorName || plan.vendorCode;

  function vendorText(v) {
    return TeacherVenderStore.nameOf(v) || v;
  }

  var STATE_TAG = (function () {
    var ST = VenderAssignStore.STATUS;
    return { done: ST.REQUESTED, requesting: ST.REQUESTING, before: ST.BEFORE, none: ST.OPEN };
  })();

  function tagOf(key) {
    return VenderAssignStore.tag(STATE_TAG[key], 'font-size:10px;');
  }

  function afterHtml(on, from) {
    return tagOf(on ? 'done' : from);
  }

  function sameTeacher(p, q) {
    return vendorText(q.vendor) === vendorText(p.vendor) && String(q.teacherName || '').trim() === String(p.teacherName || '').trim();
  }

  function alreadyDone(p, list) {
    return list.some(function (q) { return q.state === 'done' && sameTeacher(p, q); });
  }

  function existingOf(u) {
    var a = VenderAssignStore.find(u.classId) || {};
    return { mains: a.mains || [], subs: a.subs || [] };
  }

  function cellHtml(u, idx, role, existing, add) {
    var rec = VenderAssignStore.find(u.classId) || {};
    var reqLeft = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor === plan.vendorCode; })
      .reduce(function (t, r) { return t + (role === 'sub' ? (r.sub || 0) : (r.main || 0)); }, 0);
    var slotLeft = existing.filter(function (p) { return p.state === 'before' && !p.teacherName && p.vendor === plan.vendorCode; }).length;
    var matched = function (p) { return existing.filter(function (q) { return sameTeacher(p, q); })[0]; };
    var freeCount = add.filter(function (p) { return !matched(p); }).length;
    var slotHide = Math.min(freeCount, slotLeft);
    var SPACER = '<span class="check-box check-sm" style="visibility:hidden;vertical-align:middle;"><input type="checkbox" style="visibility:hidden;"><span class="check-mark"></span></span> ';
    var rows = [];
    existing.forEach(function (m) {
      if (add.some(function (p) { return sameTeacher(p, m) && m.state !== 'done'; })) return;
      if (slotHide > 0 && m.state === 'before' && !m.teacherName && m.vendor === plan.vendorCode) { slotHide--; return; }
      var t = STATE_TAG[m.state];
      rows.push('<div style="margin:2px 0;">' + SPACER + (t ? VenderAssignStore.tag(t, 'font-size:10px;') + ' ' : '') + esc(vendorText(m.vendor)) + '：' + esc(m.teacherName) + '</div>');
    });
    add.forEach(function (p, i) {
      var same = matched(p);
      var from, on;
      if (same) {
        from = same.state;
        on = same.state !== 'done';
      } else if (slotLeft > 0) {
        slotLeft--;
        from = 'before';
        on = true;
      } else if (reqLeft > 0) {
        reqLeft--;
        from = 'requesting';
        on = true;
      } else {
        from = 'none';
        on = false;
      }
      rows.push('<div class="import-line" data-from="' + from + '" style="margin:2px 0;"><label class="check-box check-sm" style="vertical-align:middle;"><input type="checkbox" class="import-check" data-idx="' + idx + '" data-role="' + role + '" data-i="' + i + '"' + (on ? ' checked' : '') + '><span class="check-mark"></span></label> ' +
        tagOf(from) + ' <span>→</span> <span class="js-after">' + afterHtml(on, from) + '</span> ' +
        esc(vendorText(p.vendor)) + '：' + esc(p.teacherName) + '</div>');
    });
    return rows.length ? rows.join('') : '-';
  }

  var newTotal = 0;
  plan.updates.forEach(function (u) {
    var ex = existingOf(u);
    (u.mains || []).forEach(function (p) { if (!alreadyDone(p, ex.mains)) newTotal++; });
    (u.subs || []).forEach(function (p) { if (!alreadyDone(p, ex.subs)) newTotal++; });
  });
  if (!newTotal && !noPlan) {
    sessionStorage.removeItem('venderImportPlan');
    var tableCard = document.querySelector('.modal-body .table-card');
    if (tableCard) tableCard.style.display = 'none';
    MessageDialog.show('反映する内容がありません');
  }
  if (newTotal) plan.updates.forEach(function (u, idx) {
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
    if (!e.target.classList.contains('import-check')) return;
    var line = e.target.closest('.import-line');
    if (line) line.querySelector('.js-after').innerHTML = afterHtml(e.target.checked, line.getAttribute('data-from'));
    updateCount();
  });
  updateCount();

  function mergeUnique(list, add) {
    add.forEach(function (p) {
      var same = list.filter(function (q) { return sameTeacher(p, q); })[0];
      if (!same) {
        var slot = list.filter(function (q) { return q.state === 'before' && !q.teacherName && q.vendor === p.vendor; })[0];
        if (slot) { slot.teacherName = p.teacherName; slot.state = 'done'; } else { list.push(p); }
        return;
      }
      if (same.state !== 'done') same.state = 'done';
    });
    return list;
  }

  $('importApply').addEventListener('click', function () {
    if (!checkedBoxes().length) {
      MessageDialog.show('反映する内容がありません');
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
